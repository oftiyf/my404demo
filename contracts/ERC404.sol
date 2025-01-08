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

  function getERC721QueueLength() public view virtual returns (uint256) {
    return _storedERC721Ids.length();
  }

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

  /// @notice Function for token approvals
  /// @dev This function assumes the operator is attempting to approve
  ///      an ERC-721 if valueOrId_ is a possibly valid ERC-721 token id.
  ///      Unlike setApprovalForAll, spender_ must be allowed to be 0x0 so
  ///      that approval can be revoked.
  function approve(
    address spender_,
    uint256 valueOrId_
  ) public virtual returns (bool) {
    if (_isValidTokenId(valueOrId_)) {
      erc721Approve(spender_, valueOrId_);
    } else {
      return erc20Approve(spender_, valueOrId_);
    }

    return true;
  }

  function erc721Approve(address spender_, uint256 id_) public virtual {
    // Intention is to approve as ERC-721 token (id).
    address erc721Owner = _getOwnerOf(id_);

    if (
      msg.sender != erc721Owner && !isApprovedForAll[erc721Owner][msg.sender]
    ) {
      revert Unauthorized();
    }

    getApproved[id_] = spender_;

    emit ERC721Events.Approval(erc721Owner, spender_, id_);
  }

  /// @dev Providing type(uint256).max for approval value results in an
  ///      unlimited approval that is not deducted from on transfers.
  function erc20Approve(
    address spender_,
    uint256 value_
  ) public virtual returns (bool) {
    // Prevent granting 0x0 an ERC-20 allowance.
    if (spender_ == address(0)) {
      revert InvalidSpender();
    }

    allowance[msg.sender][spender_] = value_;

    emit ERC20Events.Approval(msg.sender, spender_, value_);

    return true;
  }

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

  /// @notice ERC-721转账函数
  /// @dev 推荐使用此函数进行ERC721转账
  function erc721TransferFrom(
    address from_,
    address to_,
    uint256 id_
  ) public virtual {
    // 防止从0地址铸造代币
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // 防止销毁代币到0地址
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    if (from_ != _getOwnerOf(id_)) {
      revert Unauthorized();
    }

    // 检查操作者是发送者本人、被授权的操作者或被授权处理该代币
    if (
      msg.sender != from_ &&
      !isApprovedForAll[from_][msg.sender] &&
      msg.sender != getApproved[id_]
    ) {
      revert Unauthorized();
    }

    // We only need to check ERC-721 transfer exempt status for the recipient
    // since the sender being ERC-721 transfer exempt means they have already
    // had their ERC-721s stripped away during the rebalancing process.
    if (erc721TransferExempt(to_)) {
      revert RecipientIsERC721TransferExempt();
    }

    // Transfer 1 * units ERC-20 and 1 ERC-721 token.
    // ERC-721 transfer exemptions handled above. Can't make it to this point if either is transfer exempt.
    // 不需要调用 _transferERC20，因为 _transferERC721 内部已经调用了 _transferDeposits 来转移存款
    _transferERC721(from_, to_, id_);
  }

  /// @notice ERC-20代币的transferFrom函数
  /// @dev 推荐使用此函数进行ERC20转账
  function erc20TransferFrom(
    address from_,
    address to_,
    uint256 value_
  ) public virtual returns (bool) {
    // 防止从0地址铸造代币
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // 防止销毁代币到0地址
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    uint256 allowed = allowance[from_][msg.sender];

    // 检查操作者是否有足够的授权额度
    if (allowed != type(uint256).max) {
      allowance[from_][msg.sender] = allowed - value_;
    }

    // 直接转移ERC-20需要使用_transferERC20WithERC721函数
    // 在函数内部处理ERC-721豁免
    return _transferERC20WithERC721(from_, to_, value_);
  }

  /// @notice Function for ERC-20 transfers.
  /// @dev This function assumes the operator is attempting to transfer as ERC-20
  ///      given this function is only supported on the ERC-20 interface.
  ///      Treats even large amounts that are valid ERC-721 ids as ERC-20s.
  function transfer(address to_, uint256 value_) public virtual returns (bool) {
    // Prevent burning tokens to 0x0.
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    // Transferring ERC-20s directly requires the _transferERC20WithERC721 function.
    // Handles ERC-721 exemptions internally.
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

    if (
      to_.code.length != 0 &&
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

  /// @notice Function for self-exemption
  function setSelfERC721TransferExempt(bool state_) public virtual {
    _setERC721TransferExempt(msg.sender, state_);
  }

  /// @notice Function to check if address is transfer exempt
  function erc721TransferExempt(
    address target_
  ) public view virtual returns (bool) {
    return target_ == address(0) || _erc721TransferExempt[target_];
  }

  /// @notice For a token token id to be considered valid, it just needs
  ///         to fall within the range of possible token ids, it does not
  ///         necessarily have to be minted yet.
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
    _transferERC721(from_, to_, id_);
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
        _retrieveOrMintERC721(to_, units, true);
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
      // 情况4) 发送者和接收者都不是ERC-721豁免
      uint256 nftsToTransfer = value_ / units;
      for (uint256 i = 0; i < nftsToTransfer; ) {
        uint256 indexOfLastToken = _owned[from_].length - 1;
        uint256 tokenId = _owned[from_][indexOfLastToken];
        _transferERC721(from_, to_, tokenId);
        unchecked {
          ++i;
        }
      }

      if (
        erc20BalanceOfSenderBefore / units - erc20BalanceOf(from_) / units >
        nftsToTransfer
      ) {
        _withdrawAndStoreERC721(from_);
      }

      if (
        erc20BalanceOf(to_) / units - erc20BalanceOfReceiverBefore / units >
        nftsToTransfer
      ) {
        // 接收者获得新的整数代币时，只获取价值为1的NFT
        _retrieveOrMintERC721(to_, units, true);
      }
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
  function _retrieveSingleNFT(address to_, uint256 targetAmount_) private {
    if (!_storedERC721Ids.empty()) {
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
    
    // 如果没找到匹配的且数量足够，铸造新的
    revert InvalidAmount(); // 如果没有找到匹配价值的NFT，则回退
  }

  // 内部函数：获取多个价值为1的NFT
  function _retrieveMultipleNFTs(address to_, uint256 availableAmount_) private {
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
    // 如果是中间元素，需要重新组织队列
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
        }
        
        unchecked { ++i; }
    }
  }

  /// @notice Internal function for ERC-721 deposits to bank (this contract).
  /// @dev This function will allow depositing of ERC-721s to the bank, which can be retrieved by future minters.
  // Does not handle ERC-721 exemptions.
  function _withdrawAndStoreERC721(address from_) internal virtual {
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // Retrieve the latest token added to the owner's stack (LIFO).
    uint256 id = _owned[from_][_owned[from_].length - 1];

    // 在NFT被拆分前保存存款记录
    _handleNFTSplit(id);

    // Transfer to 0x0.
    // Does not handle ERC-721 exemptions.
    _transferERC721(from_, address(0), id);

    // Record the token in the contract's bank queue.
    _storedERC721Ids.pushFront(id);
  }

  /// @notice Initialization function to set pairs / etc, saving gas by avoiding mint / burn on unnecessary targets
  function _setERC721TransferExempt(
    address target_,
    bool state_
  ) internal virtual {
    if (target_ == address(0)) {
      revert InvalidExemption();
    }

    // Adjust the ERC721 balances of the target to respect exemption rules.
    // Despite this logic, it is still recommended practice to exempt prior to the target
    // having an active balance.
    if (state_) {
      _clearERC721Balance(target_);
    } else {
      _reinstateERC721Balance(target_);
    }

    _erc721TransferExempt[target_] = state_;
  }

  /// @notice Function to reinstate balance on exemption removal
  function _reinstateERC721Balance(address target_) private {
    uint256 expectedERC721Balance = erc20BalanceOf(target_) / units;
    uint256 actualERC721Balance = erc721BalanceOf(target_);

    for (uint256 i = 0; i < expectedERC721Balance - actualERC721Balance; ) {
      // Transfer ERC721 balance in from pool
      _retrieveOrMintERC721(target_, 1, true);
      unchecked {
        ++i;
      }
    }
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
  function depositTokens(uint256 tokenId_, address tokenAddress_, uint256 amount_) public {
    // 验证 NFT 存在且调用者是所有者
    address owner = _getOwnerOf(tokenId_);
    if (owner != msg.sender) {
      revert Unauthorized();
    }

    // 如果注入的是本代币，直接从用户余额中扣除
    if (tokenAddress_ == address(this)) {
      require(balanceOf[msg.sender] >= amount_, "Insufficient balance");
      _transferERC20(msg.sender, address(this), amount_);
    } else {
      // 对于其他 ERC20 代币，需要先授权再转账
      IERC20 token = IERC20(tokenAddress_);
      require(token.transferFrom(msg.sender, address(this), amount_), "Transfer failed");
    }

    // 记录存款
    _tokenDeposits[tokenId_].push(TokenDeposit({
      tokenAddress: tokenAddress_,
      amount: amount_
    }));
  }

  /// @notice 从指定的 NFT 中提取 ERC20 代币
  /// @param tokenId_ NFT的ID
  /// @param depositIndex_ 存款索引
  function withdrawTokens(uint256 tokenId_, uint256 depositIndex_) public override {
    // 验证 NFT 存在且调用者是所有者
    address owner = _getOwnerOf(tokenId_);
    if (owner != msg.sender) {
      revert Unauthorized();
    }

    // 获取存款信息
    require(depositIndex_ < _tokenDeposits[tokenId_].length, "Invalid deposit index");
    TokenDeposit storage deposit = _tokenDeposits[tokenId_][depositIndex_];
    
    uint256 amount = deposit.amount;
    address tokenAddress = deposit.tokenAddress;

    // 删除存款记录
    _removeDeposit(tokenId_, depositIndex_);

    // 如果是本代币，直接从合约转给用户
    if (tokenAddress == address(this)) {
      _transferERC20(address(this), msg.sender, amount);
    } else {
      // 对于其他 ERC20 代币
      IERC20 token = IERC20(tokenAddress);
      require(token.transfer(msg.sender, amount), "Transfer failed");
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
  function _beforeTokenTransfer(address from_, address to_, uint256 tokenId_) internal virtual {
    if (from_ != address(0) && to_ != address(0)) { // 排除铸造和销毁
      require(_tokenDeposits[tokenId_].length == 0, "Must withdraw deposits before transfer");
    }
  }

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
