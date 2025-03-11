//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC404} from "./interfaces/IERC404.sol";
import {DoubleEndedQueue} from "./lib/DoubleEndedQueue.sol";
import {ERC721Events} from "./lib/ERC721Events.sol";
import {ERC20Events} from "./lib/ERC20Events.sol";
import {ERC404Deposits} from "./ERC404Deposits.sol";  // 确保正确导入
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract ERC404 is IERC404,ERC404Deposits{
  // 来源于 @openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol
  using DoubleEndedQueue for DoubleEndedQueue.Uint256Deque;

  
  /// @dev The queue of ERC-721 tokens stored in the contract.
  DoubleEndedQueue.Uint256Deque private _storedERC721Ids;
  /// @dev Token name
  string public name;

  /// @dev Token symbol
  string public symbol;

  /// @dev Decimals for ERC-20 representation
  uint8 public immutable decimals;

  /// @dev Units for ERC-20 representation
  uint256 public immutable units;

  /// @dev Total supply in ERC-20 representation
  uint256 public totalSupply;

  /// @dev Current mint counter which also represents the highest
  ///      minted id, monotonically increasing to ensure accurate ownership
  uint256 public minted;

  /// @dev Initial chain id for EIP-2612 support
  uint256 internal immutable _INITIAL_CHAIN_ID;

  /// @dev Initial domain separator for EIP-2612 support
  bytes32 internal immutable _INITIAL_DOMAIN_SEPARATOR;

  mapping(uint256 => bool) internal _isSplit;


  /// @dev Balance of user in ERC-20 representation
  mapping(address => uint256) public balanceOf;

  /// @dev Allowance of user in ERC-20 representation
  mapping(address => mapping(address => uint256)) public allowance;

  /// @dev Approval in ERC-721 representaion
  mapping(uint256 => address) public getApproved;

  /// @dev Approval for all in ERC-721 representation
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  /// @dev Packed representation of ownerOf and owned indices
  mapping(uint256 => uint256) internal _ownedData;

  /// @dev Array of owned ids in ERC-721 representation
  mapping(address => uint256[]) internal _owned;

  /// @dev Addresses that are exempt from ERC-721 transfer, typically for gas savings (pairs, routers, etc)
  mapping(address => bool) internal _erc721TransferExempt;

  /// @dev EIP-2612 nonces
  mapping(address => uint256) public nonces;

  /// @dev Address bitmask for packed ownership data
  uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;

  /// @dev Owned index bitmask for packed ownership data
  uint256 private constant _BITMASK_OWNED_INDEX = ((1 << 96) - 1) << 160;

  /// @dev Constant for token id encoding
  uint256 public constant ID_ENCODING_PREFIX = 1 << 255;

  error InvalidAmount();
  

  constructor(string memory name_, string memory symbol_, uint8 decimals_) {
    name = name_;
    symbol = symbol_;

    if (decimals_ < 18) {
      revert DecimalsTooLow();
    }

    decimals = decimals_;
    units = 10 ** decimals;

    // EIP-2612 initialization
    _INITIAL_CHAIN_ID = block.chainid;
    _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
  }



  /// @notice Function to find owner of a given ERC-721 token
  function ownerOf(
    uint256 id_
  ) public view virtual returns (address erc721Owner) {
    erc721Owner = _getOwnerOf(id_);

    if (!_isValidTokenId(id_)) {
      revert InvalidTokenId();
    }

    if (erc721Owner == address(0)) {
      revert NotFound();
    }
  }

  function owned(
    address owner_
  ) public view virtual returns (uint256[] memory) {
    return _owned[owner_];
  }

  function erc721BalanceOf(
    address owner_
  ) public view virtual returns (uint256) {
    return _owned[owner_].length;
  }

  function erc20BalanceOf(
    address owner_
  ) public view virtual returns (uint256) {
    return balanceOf[owner_];
  }

  function erc20TotalSupply() public view virtual returns (uint256) {
    return totalSupply;
  }

  function erc721TotalSupply() public view virtual returns (uint256) {
    return minted;
  }

  /// @notice 获取当前存储在队列中的ERC721代币数量
  /// @dev 返回等待被转换为ERC721的代币ID数量
  /// @return 返回队列中存储的ERC721代币ID的数量
  function getERC721QueueLength() public view virtual returns (uint256) {
    return _storedERC721Ids.length();
  }

  /// @notice 获取队列中指定范围的ERC721代币ID
  /// @dev 从队列中获取从start_开始的count_个代币ID
  /// @param start_ 起始索引位置
  /// @param count_ 要获取的代币数量
  /// @return 返回指定范围内的代币ID数组
  function getERC721TokensInQueue(
    uint256 start_,
    uint256 count_
  ) public view virtual returns (uint256[] memory) {
    uint256[] memory tokensInQueue = new uint256[](count_);

    for (uint256 i = start_; i < start_ + count_; ) {
      tokensInQueue[i - start_] = _storedERC721Ids.at(i);

      unchecked {
        ++i;
      }
    }

    return tokensInQueue;
  }

  /// @notice tokenURI must be implemented by child contract
  function tokenURI(uint256 id_) public view virtual returns (string memory);
  
  //就是20的approve 
  function approve(
    address spender_,
    uint256 value_
  ) public virtual returns (bool) {
    if (spender_ == address(0)) {
      revert InvalidSpender();
    }
    //这个地方检查一下是不是tokenid
    if (_isValidTokenId(value_)) {
      erc721Approve(spender_, value_);
    }
    else{
    allowance[msg.sender][spender_] = value_;

    emit ERC20Events.Approval(msg.sender, spender_, value_);
    }
    return true;
  }

  function erc721Approve(address spender_, uint256 id_) public virtual {
    // Intention is to approve as ERC-721 token (id).
    address erc721Owner = _getOwnerOf(id_);

    if (
      // 检查调用者是否为NFT所有者，或者是否被所有者授权过(通过setApprovalForAll)
      msg.sender != erc721Owner && !isApprovedForAll[erc721Owner][msg.sender]
    ) {
      revert Unauthorized();
    }

    getApproved[id_] = spender_;

    emit ERC721Events.Approval(erc721Owner, spender_, id_);
  }

  //@audit 这里注释掉了，但是没有删除，可能需要删除 
  // function erc20Approve(
  //   address spender_,
  //   uint256 value_
  // ) internal virtual returns (bool) {
  //   // 防止授予0x0一个ERC-20授权
  //   if (spender_ == address(0)) {
  //     revert InvalidSpender();
  //   }
  //   allowance[msg.sender][spender_] = value_;

  //   emit ERC20Events.Approval(msg.sender, spender_, value_);

  //   return true;
  // }

  /// @notice Function for ERC-721 approvals
  function setApprovalForAll(address operator_, bool approved_) public virtual {
    // Prevent approvals to 0x0.
    if (operator_ == address(0)) {
      revert InvalidOperator();
    }
    isApprovedForAll[msg.sender][operator_] = approved_;
    emit ERC721Events.ApprovalForAll(msg.sender, operator_, approved_);
  }

  /// @notice 用于混合转账的函数，操作者可能与from地址不同
  /// @dev 如果valueOrId是有效的代币ID，则该函数假定操作者试图转移ERC-721代币
  function transferFrom(
    address from_,
    address to_,
    uint256 valueOrId_
  ) public virtual returns (bool) {
    // 检查valueOrId_是否为有效的NFT代币ID
    // 如果是有效ID，则按ERC721代币方式处理转账
    if (_isValidTokenId(valueOrId_)) {
      erc721TransferFrom(from_, to_, valueOrId_);
    } else {
      // 意图作为ERC-20代币（数量）转移
      return erc20TransferFrom(from_, to_, valueOrId_);
    }

    return true;
  }
//这里就是做了检查，实际的转账在_transferERC721
  function erc721TransferFrom(
    address from_,
    address to_,
    uint256 id_
  ) public virtual {
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    if (from_ != _getOwnerOf(id_)) {
      revert Unauthorized();
    }

    if (
      msg.sender != from_ &&
      !isApprovedForAll[from_][msg.sender] &&
      msg.sender != getApproved[id_]
    ) {
      revert Unauthorized();
    }

    if (erc721TransferExempt(to_)) {
      revert RecipientIsERC721TransferExempt();
    }

    _transferERC721(from_, to_, id_);
  }
//这里就是做了检查，实际的转账在_transferERC20WithERC721
  function erc20TransferFrom(
    address from_,
    address to_,
    uint256 value_
  ) public virtual returns (bool) {
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    uint256 allowed = allowance[from_][msg.sender];

    if (allowed != type(uint256).max) {
      allowance[from_][msg.sender] = allowed - value_;
    }

    return _transferERC20WithERC721(from_, to_, value_);
  }

  /// @notice Function for ERC-20 transfers.
  /// @dev This function assumes the operator is attempting to transfer as ERC-20
  ///      given this function is only supported on the ERC-20 interface.
  ///      Treats even large amounts that are valid ERC-721 ids as ERC-20s.
  function transfer(address to_, uint256 value_) public virtual returns (bool) {
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }
    return _transferERC20WithERC721(msg.sender, to_, value_);
  }

  /// @notice Function for ERC-721 transfers with contract support.
  /// This function only supports moving valid ERC-721 ids, as it does not exist on the ERC-20
  /// spec and will revert otherwise.
  function safeTransferFrom(
    address from_,
    address to_,
    uint256 id_
  ) public virtual {
    safeTransferFrom(from_, to_, id_, "");
  }

  /// @notice Function for ERC-721 transfers with contract support and callback data.
  /// This function only supports moving valid ERC-721 ids, as it does not exist on the
  /// ERC-20 spec and will revert otherwise.
  function safeTransferFrom(
    address from_,
    address to_,
    uint256 id_,
    bytes memory data_
  ) public virtual {
    if (!_isValidTokenId(id_)) {
      revert InvalidTokenId();
    }

    transferFrom(from_, to_, id_);

    // 这里的检查逻辑是:
    // 1. 首先检查接收地址是否为合约(to_.code.length != 0)
    // 2. 如果是合约,则要求该合约必须正确实现ERC721Receiver接口
    // 3. 如果接收地址是EOA(普通账户),则不需要做任何检查
    // 所以这个safeTransferFrom函数对合约账户有额外的安全检查,
    // 但对普通账户来说和普通的transferFrom没有区别
    if (
      to_.code.length != 0 &&
      // 这里调用了接收合约的onERC721Received函数,并检查返回值是否等于预期的selector
      // 是一个外部调用,调用to_地址的onERC721Received函数
      // 防重入的关键点:
      // 1. 在调用外部合约前,已经完成了所有状态变更(transferFrom已执行完)
      // 2. 这个检查是在最后执行的,即使被重入也不会影响之前的状态变更
      // 3. 通过检查返回值必须等于selector来确保接收合约正确实现了接口
      // 4. 如果接收合约在onERC721Received中尝试重入,由于状态已更新,会失败
      IERC721Receiver(to_).onERC721Received(msg.sender, from_, id_, data_) !=
      IERC721Receiver.onERC721Received.selector
    ) {
      revert UnsafeRecipient();
    }
  }

  /// @notice EIP-2612 许可函数（仅支持ERC-20）
  /// @dev 如果permit的value值设为type(uint256).max，将产生一个无限制的授权额度，
  ///      在转账时不会从该额度中扣除
  function permit(
    address owner_,
    address spender_,
    uint256 value_,
    uint256 deadline_,
    uint8 v_,
    bytes32 r_,
    bytes32 s_
  ) public virtual {
    if (deadline_ < block.timestamp) {
      revert PermitDeadlineExpired();
    }

    // permit不能用于ERC-721代币的授权，所以要确保
    // value值不在有效的ERC-721代币ID范围内
    if (_isValidTokenId(value_)) {
      revert InvalidApproval();
    }

    if (spender_ == address(0)) {
      revert InvalidSpender();
    }

    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR(),
            keccak256(
              abi.encode(
                keccak256(
                  "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner_,
                spender_,
                value_,
                nonces[owner_]++,
                deadline_
              )
            )
          )
        ),
        v_,
        r_,
        s_
      );

      if (recoveredAddress == address(0) || recoveredAddress != owner_) {
        revert InvalidSigner();
      }

      allowance[recoveredAddress][spender_] = value_;
    }

    emit ERC20Events.Approval(owner_, spender_, value_);
  }

  /// @notice Returns domain initial domain separator, or recomputes if chain id is not equal to initial chain id
  /// @notice 返回域分隔符。如果当前链ID等于初始链ID，则返回初始域分隔符；否则重新计算域分隔符
  /// @dev 这个函数用于EIP-2612的permit功能，域分隔符是用来防止跨链重放攻击的
  /// @return bytes32 当前的域分隔符
  function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
    return
      block.chainid == _INITIAL_CHAIN_ID
        ? _INITIAL_DOMAIN_SEPARATOR
        : _computeDomainSeparator();
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual returns (bool) {
    return
      interfaceId == type(IERC404).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  /// 设置自己为ERC721豁免
  //@audit 这里设置自己为ERC721豁免，但是会导致已经铸造的NFT被销毁
  function setSelfERC721TransferExempt(bool state_) public virtual {
    _setERC721TransferExempt(msg.sender, state_);
  }

  /// @notice Function to check if address is transfer exempt
  function erc721TransferExempt(
    address target_
  ) public view virtual returns (bool) {
    return target_ == address(0) || _erc721TransferExempt[target_];
  }

  /// @notice 判断代币ID是否有效
  /// @dev 一个代币ID要被认为是有效的，只需要满足以下条件:
  ///      1. ID必须大于ID编码前缀(ID_ENCODING_PREFIX)
  ///      2. ID不能等于uint256的最大值
  ///      注意:代币ID不需要已经被铸造,只要在有效范围内即可
  function _isValidTokenId(uint256 id_) internal pure returns (bool) {
    return id_ > ID_ENCODING_PREFIX && id_ != type(uint256).max;
  }

  /// @notice Internal function to compute domain separator for EIP-2612 permits
  function _computeDomainSeparator() internal view virtual returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          ),
          keccak256(bytes(name)),
          keccak256("1"),
          block.chainid,
          address(this)
        )
      );
  }

  /// @notice 这是最底层的 ERC-20 转账函数，用于普通的 ERC-20 转账和铸造
  /// @dev 注意该函数允许与 0x0 地址之间的转账
  function _transferERC20(
    address from_,
    address to_,
    uint256 value_
  ) internal virtual {
    // 铸造是一个特殊情况，我们不需要检查发送者的余额，只需增加总供应量
    if (from_ == address(0)) {
      totalSupply += value_;
    } else {
      // 从发送者余额中扣除金额
      balanceOf[from_] -= value_;
    }

    // 更新接收者的余额
    // 可以使用unchecked因为在铸造时已检查了totalSupply的增加，在转账时已检查了余额扣除
    unchecked {
      balanceOf[to_] += value_;
    }

    emit ERC20Events.Transfer(from_, to_, value_);
  }

  /// @notice 转移 ERC721 及其内部存储的 ERC20 资产
  function _transferERC721(address from_, address to_, uint256 id_) internal virtual {
    // 转移与NFT关联的所有存款
    _transferDeposits(id_, from_, to_);
    
    // 执行NFT转移
    _setOwnerOf(id_, to_);

    // 只有当 from_ 不是零地址时才更新发送者的数组
    if (from_ != address(0)) {
        uint256 updatedId = _owned[from_][_owned[from_].length - 1];
        uint256 index = _getOwnedIndex(id_);
        _owned[from_][index] = updatedId;
        _owned[from_].pop();
        _setOwnedIndex(updatedId, index);
    }

    // 更新接收者的 owned 数组
    _owned[to_].push(id_);
    _setOwnedIndex(id_, _owned[to_].length - 1);
    
    // 清除授权
    delete getApproved[id_];

    emit ERC721Events.Transfer(from_, to_, id_);
  }

  /// @notice ERC-20转账的内部函数，同时处理可能需要的ERC-721转账
  /// @dev 处理ERC-721豁免情况，默认只获取价值为1的NFT
  function _transferERC20WithERC721(
    address from_,
    address to_,
    uint256 value_
  ) internal virtual returns (bool) {
    uint256 erc20BalanceOfSenderBefore = erc20BalanceOf(from_);
    uint256 erc20BalanceOfReceiverBefore = erc20BalanceOf(to_);

    _transferERC20(from_, to_, value_);

    bool isFromERC721TransferExempt = erc721TransferExempt(from_);
    bool isToERC721TransferExempt = erc721TransferExempt(to_);

    if (isFromERC721TransferExempt && isToERC721TransferExempt) {
      // 情况1) 发送者和接收者都是ERC-721豁免。不需要转移ERC-721。
    } else if (isFromERC721TransferExempt) {
      // 情况2) 发送者是ERC-721豁免，接收者不是
      uint256 tokensToRetrieveOrMint = (balanceOf[to_] / units) -
        (erc20BalanceOfReceiverBefore / units);
      for (uint256 i = 0; i < tokensToRetrieveOrMint; ) {
        // 每次都只获取价值为1的NFT
        _retrieveOrMintERC721(to_, units, false);
        unchecked {
          ++i;
        }
      }
    } else if (isToERC721TransferExempt) {
      // 情况3) 发送者不是ERC-721豁免，接收者是
      uint256 tokensToWithdrawAndStore = (erc20BalanceOfSenderBefore / units) -
        (balanceOf[from_] / units);
      for (uint256 i = 0; i < tokensToWithdrawAndStore; ) {
        _withdrawAndStoreERC721(from_);
        unchecked {
          ++i;
        }
      }
    } else {
      // 情况4) 发送者和接收者都不是ERC-721豁免，直接转最外层的NFT
      uint256 nftsToTransfer = value_ / units;
      for (uint256 i = 0; i < nftsToTransfer; ) {
        uint256 indexOfLastToken = _owned[from_].length - 1;
        uint256 tokenId = _owned[from_][indexOfLastToken];
        _transferERC721(from_, to_, tokenId);
        unchecked {
          ++i;
        }
      }

      // 在情况4中，由于发送者和接收者都不是ERC-721豁免，
      // 且我们已经按照value_/units的数量转移了NFT，
      // 不会出现需要额外存储或获取NFT的情况
    }

    return true;
  }

  /// @notice Internal function for ERC20 minting
  /// @dev This function will allow minting of new ERC20s.
  ///      If mintCorrespondingERC721s_ is true, and the recipient is not ERC-721 exempt, it will
  ///      also mint the corresponding ERC721s.
  /// Handles ERC-721 exemptions.
  function _mintERC20(address to_, uint256 value_) internal virtual {
    /// You cannot mint to the zero address (you can't mint and immediately burn in the same transfer).
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    if (totalSupply + value_ > ID_ENCODING_PREFIX) {
      revert MintLimitReached();
    }

    _transferERC20WithERC721(address(0), to_, value_);
  }

  /// @notice ERC-721代币铸造和从银行取回的内部函数
  /// @dev 该函数允许铸造新的ERC-721代币或从银行取回代币
  /// @param to_ 接收者地址
  /// @param availableAmount_ 用户可用的代币数量
  /// @param singleNFT_ true表示只接收一个NFT，false表示可以接收多个NFT
  function _retrieveOrMintERC721(
    address to_, 
    uint256 availableAmount_,
    bool singleNFT_
  ) internal virtual {
    if (to_ == address(0)) {
        revert InvalidRecipient();
    }

    if (singleNFT_) {
        // 单个NFT模式：寻找价值等于availableAmount_的NFT
        _retrieveSingleNFT(to_, availableAmount_);
    } else {
        // 多个NFT模式：尽可能多地获取价值为1的NFT
        _retrieveMultipleNFTs(to_, availableAmount_);
    }
  }

  // 内部函数：获取单个特定价值的NFT
  function _retrieveSingleNFT(address to_, uint256 targetAmount_) internal virtual {
    if (!_storedERC721Ids.empty()) { // _storedERC721Ids是一个存储被拆分的NFT的ID的队列数据结构，在ERC404.sol文件中定义。当一个NFT被拆分时，其ID会被存入这个队列中，等待之后被重新组合或取回。
        // 遍历存储的ID，寻找价值匹配的
        uint256 i = 0;
        uint256 storedIdsLength = _storedERC721Ids.length();
        
        while (i < storedIdsLength) {
            uint256 candidateId = _storedERC721Ids.at(i);
            uint256 requiredAmount = _requiredAmount[candidateId];
            
            // 检查是否找到价值匹配的NFT
            if (requiredAmount == targetAmount_ && _canRestoreNFT(candidateId)) {
                _storedERC721Ids.popFront();
                _handleNFTRestore(candidateId);
                _transferERC721(address(0), to_, candidateId);
                return;
            }
            i++;
        }
    }
    
    // 如果没找到匹配的，尝试拆分为多个价值为1的NFT
    _retrieveMultipleNFTs(to_, targetAmount_);
  }

  // 内部函数：获取多个价值为1的NFT
  function _retrieveMultipleNFTs(address to_, uint256 availableAmount_) internal virtual {
    uint256 nftsToMint = availableAmount_ / units;
    
    for (uint256 i = 0; i < nftsToMint;) {
        // 尝试从存储中找价值为1的NFT
        bool found = false;
        if (!_storedERC721Ids.empty()) {
            uint256 j = 0;
            uint256 storedIdsLength = _storedERC721Ids.length();
            
            while (j < storedIdsLength && !found) {
                uint256 candidateId = _storedERC721Ids.at(j);
                if (_requiredAmount[candidateId] == units && _canRestoreNFT(candidateId)) {
                    
                    if (j == 0) {
                      _storedERC721Ids.popFront();
                    } else if (j == _storedERC721Ids.length() - 1) {
                      _storedERC721Ids.popBack();
                    } else {
                      uint256 length = _storedERC721Ids.length();
                      for (uint256 k = j; k < length - 1; k++) {
                        uint256 nextValue = _storedERC721Ids.at(k + 1);
                        _storedERC721Ids.popBack();
                        _storedERC721Ids.pushFront(nextValue);
                      }
                      _storedERC721Ids.popBack();
                    }
                    _handleNFTRestore(candidateId);
                    _transferERC721(address(0), to_, candidateId);
                    found = true;
                }
                j++;
            }
        }
        
        // 如果没找到价值为1的NFT，铸造新的
        if (!found) {
            ++minted;
            if (minted == type(uint256).max) {
                revert MintLimitReached();
            }
            uint256 newId = ID_ENCODING_PREFIX + minted;
            _transferERC721(address(0), to_, newId);
            //这里做一下自动
            // 为新铸造的NFT添加初始存款记录
            _tokenDeposits[newId].push(TokenDeposit({
                tokenAddress: address(this),  // 原生ERC20代币地址
                amount: units               // 存入1个单位的代币
            }));
        }
        
        unchecked { ++i; }
    }
  }

  /// @notice 内部函数,用于将ERC-721存入银行(即本合约)
  /// @dev 这个函数允许将ERC-721存入银行,供未来的铸币者取回使用
  /// 主要功能:
  /// 1. 从用户地址中取出最新添加的NFT(后进先出)
  /// 2. 在NFT被拆分前保存其存款记录
  /// 3. 将NFT转移到0地址(相当于销毁)
  /// 4. 将该NFT ID记录到合约的存储队列中
  /// 注意:不处理ERC-721豁免情况
  function _withdrawAndStoreERC721(address from_) internal virtual {
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // 获取所有者堆栈中最新添加的代币(后进先出)
    uint256 id = _owned[from_][_owned[from_].length - 1];

    // 在NFT被拆分前保存存款记录
    _handleNFTSplit(id);

    // 转移到0地址(相当于销毁)
    // 不处理ERC-721豁免情况
    _transferERC721(from_, address(0), id);

    // 将代币记录到合约的银行队列中
    _storedERC721Ids.pushFront(id);
  }

  function _setERC721TransferExempt(
    address target_,
    bool state_
  ) internal virtual {
    if (target_ == address(0)) {
      revert InvalidExemption();
    }
    if (state_) {
      _clearERC721Balance(target_);
    } else {
      _reinstateERC721Balance(target_);
    }

    _erc721TransferExempt[target_] = state_;
  }

  /// @notice 当地址从豁免名单中移除时恢复其 ERC721 余额
  /// @dev 该函数用于当一个地址不再被豁免时，根据其 ERC20 余额恢复相应数量的 NFT
  /// 计算方法:
  /// 1. 根据地址的 ERC20 余额计算应持有的 NFT 数量
  /// 2. 获取地址当前实际持有的 NFT 数量
  /// 3. 如果应持有数量大于实际持有数量，则从 NFT 池中取回或铸造新的 NFT 来补足差额
  function _reinstateERC721Balance(address target_) private {
    uint256 expectedERC721Balance = erc20BalanceOf(target_) / units;
    uint256 actualERC721Balance = erc721BalanceOf(target_);

    for (uint256 i = 0; i < expectedERC721Balance - actualERC721Balance; ) {
      // Transfer ERC721 balance in from pool
      _retrieveOrMintERC721(target_, units, false);
      unchecked {
        ++i;
      }
    }
  }

  function trygetmorevalue(uint256 amountin) public {
    _transferERC20WithERC721(msg.sender, address(this), amountin);
    _retrieveOrMintERC721(msg.sender, amountin, true);
    _transferERC20(address(this), msg.sender, amountin);
    
  }

  /// @notice Function to clear balance on exemption inclusion
  function _clearERC721Balance(address target_) private {
    uint256 erc721Balance = erc721BalanceOf(target_);

    for (uint256 i = 0; i < erc721Balance; ) {
      // Transfer out ERC721 balance
      _withdrawAndStoreERC721(target_);
      unchecked {
        ++i;
      }
    }
  }

  function _getOwnerOf(
    uint256 id_
  ) internal view virtual returns (address ownerOf_) {
    uint256 data = _ownedData[id_];

    assembly {
      ownerOf_ := and(data, _BITMASK_ADDRESS)
    }
  }

  function _setOwnerOf(uint256 id_, address owner_) internal virtual {
    uint256 data = _ownedData[id_];

    assembly {
      data := add(
        and(data, _BITMASK_OWNED_INDEX),
        and(owner_, _BITMASK_ADDRESS)
      )
    }

    _ownedData[id_] = data;
  }

  function _getOwnedIndex(
    uint256 id_
  ) internal view virtual returns (uint256 ownedIndex_) {
    uint256 data = _ownedData[id_];

    assembly {
      ownedIndex_ := shr(160, data)
    }
  }

  function _setOwnedIndex(uint256 id_, uint256 index_) internal virtual {
    uint256 data = _ownedData[id_];

    if (index_ > _BITMASK_OWNED_INDEX >> 160) {
      revert OwnedIndexOverflow();
    }

    assembly {
      data := add(
        and(data, _BITMASK_ADDRESS),
        and(shl(160, index_), _BITMASK_OWNED_INDEX)
      )
    }

    _ownedData[id_] = data;
  }

  /// @notice 向指定的 NFT 注入 ERC20 代币
  /// @param tokenId_ NFT的ID
  /// @param tokenAddress_ ERC20代币的地址
  /// @param amount_ 注入的数量
  function depositTokens(uint256 tokenId_, address tokenAddress_, uint256 amount_) public override {
    // 验证 NFT 存在且调用者是所有者
    ///要去amouunt必须小于余额
    require(amount_ < balanceOf[msg.sender], "Insufficient balance");
    address owner = _getOwnerOf(tokenId_);
    if (owner != msg.sender) {
      revert Unauthorized();
    }

    uint256 bedepositnftdepositbefore = _tokenDeposits[tokenId_][0].amount;
    // 如果注入的是本代币，直接从用户余额中扣除
    if (tokenAddress_ == address(this)) {
      require(balanceOf[msg.sender] >= amount_, "Insufficient balance");
      _transferERC20WithERC721(msg.sender, address(this), amount_);
      
    } else {
      // // 对于其他 ERC20 代币，需要先授权再转账
      // IERC20 token = IERC20(tokenAddress_);
      // require(token.transferFrom(msg.sender, address(this), amount_), "Transfer failed");
      //报错
      revert("now this is not support for deposit");
    }

    // 记录存款
    _tokenDeposits[tokenId_].push(TokenDeposit({
      tokenAddress: tokenAddress_,
      amount: amount_+bedepositnftdepositbefore
    }));

    // 尝试转移NFT，如果失败则不影响存款操作
    try this.transferFrom(address(this), msg.sender, tokenId_) {
      // 转移成功，无需额外操作
    } catch {
      //下面写个20的底层
      _transferERC20(address(this), msg.sender, amount_);
    }

  }


  function withdrawTokens(uint256 tokenId_) public {
    // 验证 NFT 存在且调用者是所有者
    address owner = _getOwnerOf(tokenId_);
    if (owner != msg.sender) {
      revert Unauthorized();
    }
    //获取tokenid对应的存款
    TokenDeposit[] memory deposits = getTokenDeposits(tokenId_);
    //将这个erc721转移给用户，并且携带存款
    _transferERC721(address(this), msg.sender, tokenId_); 
    //遍历存款，将每个存款的代币转移给用户
    for (uint256 i = 0; i < deposits.length; i++) {
      _transferERC20(address(this), msg.sender, deposits[i].amount);
    }
    
    
  }

  /// @notice 获取指定 NFT 的所有存款信息
  /// @param tokenId_ NFT的ID
  function getTokenDeposits(uint256 tokenId_) public view override returns (TokenDeposit[] memory) {
    return _tokenDeposits[tokenId_];
  }

  /// @notice 内部函数：移除存款记录
  function _removeDeposit(uint256 tokenId_, uint256 index_) internal override {
    require(index_ < _tokenDeposits[tokenId_].length, "Invalid index");
    
    // 将最后一个元素移到要删除的位置，然后删除最后一个元素
    if (index_ != _tokenDeposits[tokenId_].length - 1) {
      _tokenDeposits[tokenId_][index_] = _tokenDeposits[tokenId_][_tokenDeposits[tokenId_].length - 1];
    }
    _tokenDeposits[tokenId_].pop();
  }

  /// @notice 在转移 NFT 时需要确保没有存款
  // function _beforeTokenTransfer(address from_, address to_, uint256 tokenId_) internal virtual {
  //   if (from_ != address(0) && to_ != address(0)) { // 排除铸造和销毁
  //     require(_tokenDeposits[tokenId_].length == 0, "Must withdraw deposits before transfer");
  //   }
  // }

  /// @notice Transfer deposits when NFT is transferred
  /// @dev This function should be called during NFT transfer
  function _transferDeposits(uint256 tokenId_, address from_, address to_) internal virtual override {
    uint256 depositAmount = _tokenDeposits[tokenId_].length;
    if (depositAmount > 0) {
      // No need to actually move tokens since they stay in the contract
      // Just update the accounting
      emit TokensWithdrawn(tokenId_, _tokenDeposits[tokenId_][depositAmount - 1].tokenAddress, _tokenDeposits[tokenId_][depositAmount - 1].amount);
      emit TokensDeposited(tokenId_, _tokenDeposits[tokenId_][depositAmount - 1].tokenAddress, _tokenDeposits[tokenId_][depositAmount - 1].amount);
    }
  }

  /// @notice 检查是否可以恢复特定ID的NFT
  function _canRestoreNFT(uint256 tokenId_) internal view override returns (bool) {
    if (!_isSplit[tokenId_] || _splitDeposits[tokenId_].length == 0) {
      return true; // 如果NFT未被拆分或没有存款记录，可以直接恢复
    }

    // 检查存款金额是否满足要求
    TokenDeposit[] storage requiredDeposits = _splitDeposits[tokenId_];
    TokenDeposit[] storage currentDeposits = _tokenDeposits[tokenId_];
    
    if (currentDeposits.length == 0) return false;
    
    // 检查原生ERC20资产（索引0）的金额是否满足要求
    return currentDeposits[0].amount >= requiredDeposits[0].amount;
  }

  /// @notice 在NFT被恢复时恢复存款记录
  function _handleNFTRestore(uint256 tokenId_) internal override {
    if (_isSplit[tokenId_] && _splitDeposits[tokenId_].length > 0) {
      require(_canRestoreNFT(tokenId_), "Insufficient deposits to restore NFT");
      
      // 恢复存款记录
      delete _tokenDeposits[tokenId_];
      for (uint256 i = 0; i < _splitDeposits[tokenId_].length; i++) {
        _tokenDeposits[tokenId_].push(_splitDeposits[tokenId_][i]);
      }
      
      // 清除拆分记录
      delete _splitDeposits[tokenId_];
      _isSplit[tokenId_] = false;
    }
  }

  function _isOwner(address owner_, uint256 tokenId_) internal override returns (bool) {
    return _getOwnerOf(tokenId_) == owner_;
  }

  function _transfer(address from_, address to_, uint256 amount_) internal override returns (bool) {
    _transferERC20(from_, to_, amount_);
    return true;
  }

  function _transferFromSender(address from_, address to_, uint256 amount_) internal override returns (bool) {
    return _transferERC20WithERC721(from_, to_, amount_);
  }
}
