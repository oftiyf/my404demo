//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC405} from "./interfaces/IERC405.sol";
import {DoubleEndedQueue} from "./lib/DoubleEndedQueue.sol";
import {ERC721Events} from "./lib/ERC721Events.sol";
import {ERC20Events} from "./lib/ERC20Events.sol";

abstract contract ERC405 is IERC405 {
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

  /// @dev Balance of user in ERC-20 representation
  mapping(address => uint256) public balanceOf;

  /// @dev Allowance of user in ERC-20 representation
  mapping(address => mapping(address => uint256)) public allowance;

  /// @dev Approval in ERC-721 representaion
  mapping(uint256 => address) public getApproved;

  /// @dev Approval for all in ERC-721 representation
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  /// @dev 记录NFT背后有多少token
  mapping(uint256 => uint256) public tokenIdToTokenCount;

  /// @dev 记录NFT操作的时间
  mapping(uint256 => uint256) public tokenIdToLastOperationTime;

  /// @dev 时间阈值，NFT冻结时间
  uint256 public immutable frozenTime;

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
  
  // /// @dev 冻结时间太短
  // error FrozenTimeTooShort();
  // /// @dev NFT被冻结
  // error FrozenNFT();
  // /// @dev 不需要mint价值为0的NFT
  // error ZeroValue();
  // /// @dev 不在bank中
  // error NotIn();

  /// @notice 在合约初始化确定frozenTime
  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 frozenTime_) {
    name = name_;
    symbol = symbol_;

    if (frozenTime_ < 12 hours) {
      revert FrozenTimeTooShort();
    }

    frozenTime = frozenTime_;
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

  /// @notice Function for mixed transfers from an operator that may be different than 'from'.
  /// @dev This function assumes the operator is attempting to transfer an ERC-721
  ///      if valueOrId is a possible valid token id.
  function transferFrom(
    address from_,
    address to_,
    uint256 valueOrId_
  ) public virtual returns (bool) {
    if (_isValidTokenId(valueOrId_)) {
      erc721TransferFrom(from_, to_, valueOrId_);
    } else {
      // Intention is to transfer as ERC-20 token (value).
      return erc20TransferFrom(from_, to_, valueOrId_);
    }

    return true;
  }

  /// @notice Function for ERC-721 transfers from.
  /// @dev This function is recommended for ERC721 transfers.
  function erc721TransferFrom(
    address from_,
    address to_,
    uint256 id_
  ) public virtual {
    // Prevent minting tokens from 0x0.
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // Prevent burning tokens to 0x0.
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    if (from_ != _getOwnerOf(id_)) {
      revert Unauthorized();
    }

    // Check that the operator is either the sender or approved for the transfer.
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
    // tokenIdToLastOperationTime更新只会在：
    // 1._transferERC20WithERC721时涉及到NFT背后token变动时
    // 2.withdraw函数
    // 3.deposit函数
    if(tokenIdToLastOperationTime[id_] != 0 && block.timestamp - tokenIdToLastOperationTime[id_] < frozenTime) {
      revert FrozenNFT();
    }    

    
    // Transfer 1 * units ERC-20 and 1 ERC-721 token.
    // ERC-721 transfer exemptions handled above. Can't make it to this point if either is transfer exempt.
    //_transferERC20(from_, to_, units);
    // 把NFTId背后的token全部转过去
    uint256 value = tokenIdToTokenCount[id_];
    _transferERC20(from_, to_, value);
    _transferERC721(from_, to_, id_);
  }

  /// @notice Function for ERC-20 transfers from.
  /// @dev This function is recommended for ERC20 transfers
  function erc20TransferFrom(
    address from_,
    address to_,
    uint256 value_
  ) public virtual returns (bool) {
    // Prevent minting tokens from 0x0.
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // Prevent burning tokens to 0x0.
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    uint256 allowed = allowance[from_][msg.sender];

    // Check that the operator has sufficient allowance.
    if (allowed != type(uint256).max) {
      allowance[from_][msg.sender] = allowed - value_;
    }

    // Transferring ERC-20s directly requires the _transferERC20WithERC721 function.
    // Handles ERC-721 exemptions internally.
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

  /// @notice Function for EIP-2612 permits (ERC-20 only).
  /// @dev Providing type(uint256).max for permit value results in an
  ///      unlimited approval that is not deducted from on transfers.
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

    // permit cannot be used for ERC-721 token approvals, so ensure
    // the value does not fall within the valid range of ERC-721 token ids.
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
      interfaceId == type(IERC405).interfaceId ||
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

  /// @notice This is the lowest level ERC-20 transfer function, which
  ///         should be used for both normal ERC-20 transfers as well as minting.
  /// Note that this function allows transfers to and from 0x0.
  function _transferERC20(
    address from_,
    address to_,
    uint256 value_
  ) internal virtual {
    // Minting is a special case for which we should not check the balance of
    // the sender, and we should increase the total supply.
    if (from_ == address(0)) {
      totalSupply += value_;
    } else {
      // Deduct value from sender's balance.
      balanceOf[from_] -= value_;
    }

    // Update the recipient's balance.
    // Can be unchecked because on mint, adding to totalSupply is checked, and on transfer balance deduction is checked.
    unchecked {
      balanceOf[to_] += value_;
    }

    emit ERC20Events.Transfer(from_, to_, value_);
  }

  /// @notice Consolidated record keeping function for transferring ERC-721s.
  /// @dev Assign the token to the new owner, and remove from the old owner.
  /// Note that this function allows transfers to and from 0x0.
  /// Does not handle ERC-721 exemptions.
  function _transferERC721(
    address from_,
    address to_,
    uint256 id_
  ) internal virtual {
    // If this is not a mint, handle record keeping for transfer from previous owner.
    if (from_ != address(0)) {
      // On transfer of an NFT, any previous approval is reset.
      delete getApproved[id_];

      uint256 updatedId = _owned[from_][_owned[from_].length - 1];
      if (updatedId != id_) {
        uint256 updatedIndex = _getOwnedIndex(id_);
        // update _owned for sender
        _owned[from_][updatedIndex] = updatedId;
        // update index for the moved id
        _setOwnedIndex(updatedId, updatedIndex);
      }

      // pop
      _owned[from_].pop();
    }

    // Check if this is a burn.
    if (to_ != address(0)) {
      // If not a burn, update the owner of the token to the new owner.
      // Update owner of the token to the new owner.
      _setOwnerOf(id_, to_);
      // Push token onto the new owner's stack.
      _owned[to_].push(id_);
      // Update index for new owner's stack.
      _setOwnedIndex(id_, _owned[to_].length - 1);
    } else {
      // If this is a burn, reset the owner of the token to 0x0 by deleting the token from _ownedData.
      delete _ownedData[id_];
    }

    emit ERC721Events.Transfer(from_, to_, id_);
  }

  /// @notice Internal function for ERC-20 transfers. Also handles any ERC-721 transfers that may be required.
  // Handles ERC-721 exemptions.
  function _transferERC20WithERC721(
    address from_,
    address to_,
    uint256 value_
  ) internal virtual returns (bool) {
    // uint256 erc20BalanceOfSenderBefore = erc20BalanceOf(from_);
    // uint256 erc20BalanceOfReceiverBefore = erc20BalanceOf(to_);

    _transferERC20(from_, to_, value_);

    // Preload for gas savings on branches
    bool isFromERC721TransferExempt = erc721TransferExempt(from_);
    bool isToERC721TransferExempt = erc721TransferExempt(to_);

    if (isFromERC721TransferExempt && isToERC721TransferExempt) {
    } else if (isFromERC721TransferExempt) {
      _retrieveOrMintERC721(to_, value_);
    } else if (isToERC721TransferExempt) {
      _withdrawAndStoreERC721(from_, value_);
    } else {
      _retrieveOrMintERC721(to_, value_);
      _withdrawAndStoreERC721(from_, value_);
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


  /// @notice Internal function for ERC-721 minting and retrieval from the bank.
  /// @dev 这个函数首先从bank中寻找并取出相同value_的NFT.
  ///      如果没有的话，则mint一个新的NFT.
  /// Does not handle ERC-721 exemptions.
  function _retrieveOrMintERC721(address to_, uint256 value_) internal virtual {
    if (value_ == 0) {
      revert ZeroValue();
    }

    if (!_storedERC721Ids.empty()) {
        // 遍历存储的ID，寻找价值匹配的
        uint256 i = 0;
        uint256 storedIdsLength = _storedERC721Ids.length();
        
        while (i < storedIdsLength) {
            uint256 candidateId = _storedERC721Ids.at(i);
            uint256 requiredAmount = tokenIdToTokenCount[candidateId];
            
            // 检查是否找到价值匹配的NFT
            // 需要检查对结构体的操作是否有问题
            if (requiredAmount == value_) {
                _storedERC721Ids._data[uint128(i)] = _storedERC721Ids._data[uint128(storedIdsLength)-1];
                _storedERC721Ids.popBack();
                _transferERC721(address(0), to_, candidateId);
                return;
            }
            i++;
        }
    }
    ++minted;
    if (minted == type(uint256).max) {
        revert MintLimitReached();
    }
    uint256 newId = ID_ENCODING_PREFIX + minted;
    _transferERC721(address(0), to_, newId);
    tokenIdToTokenCount[newId] = value_;
  }


  /// @notice Internal function for ERC-721 deposits to bank (this contract).
  /// @dev 这个函数此功能将允许将token全部被转移走的ERC-721存入银行.
  ///      并且扣除部分NFT背后的token.
  // Does not handle ERC-721 exemptions.
  function _withdrawAndStoreERC721(address from_, uint256 value_) internal virtual {
    if (value_ == 0) {
      revert ZeroValue();
    }
    
    if (from_ == address(0)) {
      revert InvalidSender();
    }
    uint256 remaining = value_;
    uint256 id;

    // 遍历from_的NFT，寻找价值匹配的
    uint256 number = _owned[from_].length;
    uint256[] memory ownedNFTs = _owned[from_];
    for (uint256 i = 0; i < number; i++) {
      id = ownedNFTs[i];
      uint256 NFTValue = tokenIdToTokenCount[id];
      if (NFTValue == remaining) {
        remaining = 0;
        _transferERC721(from_, address(0), id);
        _storedERC721Ids.pushFront(id);
        tokenIdToLastOperationTime[id] = 0;
        return;
      }
    }

    while (remaining > 0) {
      id = _owned[from_][_owned[from_].length - 1];
      uint256 NFTValue = tokenIdToTokenCount[id];
      if (NFTValue <= remaining) {
        remaining -= NFTValue;
        _transferERC721(from_, address(0), id);
        _storedERC721Ids.pushFront(id);
        // 回收的NFT的lastOperationTime设置为0
        // 不操作tokenIdToTokenCount数值，为了让restore函数参考
        tokenIdToLastOperationTime[id] = 0;
      } else {
        // 更新tokenIdToTokenCount数值
        // 更新tokenIdToLastOperationTime，让突然降低价值的NFT先冻结
        tokenIdToTokenCount[id] -= remaining;
        tokenIdToLastOperationTime[id] = block.timestamp;
        remaining = 0;
      }
      
    }
  }


  /// @notice Initialization function to set pairs / etc, saving gas by avoiding mint / burn on unnecessary targets
  /// @notice 该函数不能重复调用，不然会重入不断mint NFT
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
      // 用来防止重放
      require(_erc721TransferExempt[target_] == false);
      _clearERC721Balance(target_);
    } else {
      // 用来防止重放
      require(_erc721TransferExempt[target_] == true);
      _reinstateERC721Balance(target_);
    }

    _erc721TransferExempt[target_] = state_;
  }


  /// @notice Function to reinstate balance on exemption removal
  function _reinstateERC721Balance(address target_) private {
    uint256 erc20Balance = erc20BalanceOf(target_);
    _retrieveOrMintERC721(target_, erc20Balance);
  }

  /// @notice Function to clear balance on exemption inclusion
  function _clearERC721Balance(address target_) private {
    uint256 erc20Balance = erc20BalanceOf(target_);
    _withdrawAndStoreERC721(target_, erc20Balance);
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

  /// @notice 向指定的 NFT 注入 指定 NFT的 ERC20 代币
  /// @param tokenIdfrom_ 注入源头
  /// @param tokenIdto_ 被注入的NFTId
  /// @param amount_ 注入的数量
  function depositTokens(uint256 tokenIdfrom_, uint256 tokenIdto_, uint256 amount_) public virtual {
    // 验证 NFT 存在且调用者是所有者
    ///要去amount必须小于余额
    uint256 backupValue = tokenIdToTokenCount[tokenIdfrom_];
    require(amount_ <= backupValue, "Insufficient balance");
    // require(amount_ >= units, "Too low");
    address fromOwner = _getOwnerOf(tokenIdfrom_);
    address toOwner = _getOwnerOf(tokenIdto_);
    if (fromOwner != msg.sender) {
      revert Unauthorized();
    }

    _transferERC20(fromOwner, toOwner, amount_);
    
    if (amount_ < backupValue) {
      tokenIdToTokenCount[tokenIdfrom_] -= amount_;
      tokenIdToTokenCount[tokenIdto_] += amount_;
      // 不关注被注入的NFT，即不冻结被注入的NFT
      tokenIdToLastOperationTime[tokenIdfrom_] = block.timestamp;
    } else { //这个就不需要再设定amount == backupValue,因为在之前require的时候就确保了amount不会大于backupValue
      tokenIdToTokenCount[tokenIdto_] += amount_;
      _transferERC721(fromOwner, address(0), tokenIdfrom_);
      _storedERC721Ids.pushFront(tokenIdfrom_);
      tokenIdToLastOperationTime[tokenIdfrom_] = 0;
    }
  }


  /// @notice 向指定的 NFT 注入 指定 NFT的 全部 ERC20 代币
  /// @param tokenIdfrom_ 注入源头
  /// @param tokenIdto_ 被注入的NFTId
  function depositNFTalltokens(uint256 tokenIdfrom_, uint256 tokenIdto_) public virtual {
    depositTokens(tokenIdfrom_, tokenIdto_, tokenIdToTokenCount[tokenIdfrom_]);
  }

  /// @notice 向指定的 NFT 注入 ERC20 代币
  /// @param tokenIdto_ NFT的ID
  /// @param amount_ 注入的数量
  function depositTokens(uint256 tokenIdto_, uint256 amount_) public virtual {
    // 验证 NFT 存在且调用者是所有者
    ///要去amount必须小于等于余额
    require(amount_ <= balanceOf[msg.sender], "Insufficient balance");
    address toOwner = _getOwnerOf(tokenIdto_);
    _transferERC20(msg.sender, toOwner, amount_);
    tokenIdToTokenCount[tokenIdto_] += amount_;
    _withdrawAndStoreERC721(msg.sender, amount_);
  }


  function withdrawTokens(uint256 tokenId_, uint256 amount_) public virtual {
    // 验证 NFT 存在且调用者是所有者
    address owner = _getOwnerOf(tokenId_);
    if (owner != msg.sender) {
      revert Unauthorized();
    }
    uint256 backupValue = tokenIdToTokenCount[tokenId_];
    require(amount_ < backupValue, "Insufficient balance");
    tokenIdToTokenCount[tokenId_] -= amount_;
    tokenIdToLastOperationTime[tokenId_] = block.timestamp;
    _retrieveOrMintERC721(msg.sender, amount_);
  }

  /// @notice 恢复特定ID的NFT
  /// @notice 这里是等价值的恢复，还需实现非等价值恢复（花更少的钱恢复）
  function RestoreNFT(uint256 tokenId_, uint256 amount_) public virtual {
    (bool isIn, uint256 index) = _isIn(tokenId_);
    uint256 storedIdsLength = _storedERC721Ids.length();
    if (!isIn) {
      revert NotIn();
    }
    require(amount_ == tokenIdToTokenCount[tokenId_], "wrong restore balance");
    // 先从bank中取出恢复的tokenId
    _storedERC721Ids._data[uint128(index)] = _storedERC721Ids._data[uint128(storedIdsLength)-1];
    _storedERC721Ids.popBack();
    _transferERC721(address(0), msg.sender, tokenId_);
    
    
    // 把拥有的tokenID替换bank中的tokenID
    _withdrawAndStoreERC721(msg.sender, amount_);
    
  }

  

  function _isIn(uint256 tokenId_) internal view returns (bool, uint256) {
    uint256 length = _storedERC721Ids.length();
    for (uint256 i = 0; i < length; i++) {
      if (_storedERC721Ids.at(i) == tokenId_) {
        return (true, i);
      } else {
        return (false, 0);
      }
    }
  }



}