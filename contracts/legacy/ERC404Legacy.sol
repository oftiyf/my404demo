//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

abstract contract Ownable {
  event OwnershipTransferred(address indexed user, address indexed newOwner);

  error Unauthorized();
  error InvalidOwner();

  address public owner;

  modifier onlyOwner() virtual {
    if (msg.sender != owner) revert Unauthorized();

    _;
  }

  constructor(address _owner) {
    if (_owner == address(0)) revert InvalidOwner();

    owner = _owner;

    emit OwnershipTransferred(address(0), _owner);
  }

  function transferOwnership(address _owner) public virtual onlyOwner {
    if (_owner == address(0)) revert InvalidOwner();

    owner = _owner;

    emit OwnershipTransferred(msg.sender, _owner);
  }

  function revokeOwnership() public virtual onlyOwner {
    owner = address(0);

    emit OwnershipTransferred(msg.sender, address(0));
  }
}

abstract contract ERC721Receiver {
  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4) {
    return ERC721Receiver.onERC721Received.selector;
  }
}

/// @notice ERC404
///         一个高效的混合ERC20/ERC721实现
///         具有原生流动性和分数化功能。
///
///         这是一个实验性标准,旨在与现有的ERC20/ERC721支持
///         尽可能平滑地集成。
///
/// @dev    为了支持ERC20和ERC721的完整功能,
///         对供应做出了一些假设,这些假设略微限制了使用。
///         确保小数位数足够大(建议使用标准的18位),
///         因为ID实际上被编码在金额的最低范围内。
///
///         NFT在ERC20功能中以FILO队列的方式使用,
///         这是设计使然。
///
abstract contract ERC404Legacy is Ownable {
  // 事件
  event ERC20Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 amount
  );
  event Transfer(address indexed from, address indexed to, uint256 indexed id);
  event ERC721Approval(
    address indexed owner,
    address indexed spender,
    uint256 indexed id
  );
  event ApprovalForAll(
    address indexed owner,
    address indexed operator,
    bool approved
  );

  // 错误
  error NotFound();
  error AlreadyExists();
  error InvalidRecipient();
  error InvalidSender();
  error UnsafeRecipient();

  // 元数据
  /// @dev 代币名称
  string public name;

  /// @dev 代币符号
  string public symbol;

  /// @dev 分数表示的小数位数
  uint8 public immutable decimals;

  /// @dev 分数表示的总供应量
  uint256 public immutable totalSupply;

  /// @dev 当前铸造计数器,单调递增以确保准确的所有权
  uint256 public minted;

  // 映射
  /// @dev 用户在分数表示下的余额
  mapping(address => uint256) public balanceOf;

  /// @dev 用户在分数表示下的授权额度
  mapping(address => mapping(address => uint256)) public allowance;

  /// @dev 原生表示下的授权
  mapping(uint256 => address) public getApproved;

  /// @dev 原生表示下的全部授权
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  /// @dev 原生表示下的ID所有者
  mapping(uint256 => address) internal _ownerOf;

  /// @dev 原生表示下拥有的ID数组
  mapping(address => uint256[]) internal _owned;

  /// @dev _owned映射的索引跟踪
  mapping(uint256 => uint256) internal _ownedIndex;

  /// @dev 白名单地址(交易对、路由器等)可以跳过铸造/销毁以节省gas
  mapping(address => bool) public whitelist;

  // 构造函数
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256 _totalNativeSupply,
    address _owner
  ) Ownable(_owner) {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    totalSupply = _totalNativeSupply * (10 ** decimals);
  }

  /// @notice 初始化函数用于设置交易对等
  ///         通过避免对不必要目标的铸造/销毁来节省gas
  function setWhitelist(address target, bool state) public onlyOwner {
    whitelist[target] = state;
  }

  /// @notice 查找给定原生代币的所有者的函数
  function ownerOf(uint256 id) public view virtual returns (address owner) {
    owner = _ownerOf[id];

    if (owner == address(0)) {
      revert NotFound();
    }
  }

  /// @notice tokenURI必须由子合约实现
  function tokenURI(uint256 id) public view virtual returns (string memory);

  /// @notice 代币授权函数
  /// @dev 如果数量小于或等于当前最大ID,则此函数假定为ID/原生代币
  function approve(
    address spender,
    uint256 amountOrId
  ) public virtual returns (bool) {
    if (amountOrId <= minted && amountOrId > 0) {
      address owner = _ownerOf[amountOrId];

      if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
        revert Unauthorized();
      }

      getApproved[amountOrId] = spender;

      emit Approval(owner, spender, amountOrId);
    } else {
      allowance[msg.sender][spender] = amountOrId;

      emit Approval(msg.sender, spender, amountOrId);
    }

    return true;
  }

  /// @notice 原生代币授权函数
  function setApprovalForAll(address operator, bool approved) public virtual {
    isApprovedForAll[msg.sender][operator] = approved;

    emit ApprovalForAll(msg.sender, operator, approved);
  }

  /// @notice 混合转账函数
  /// @dev 如果数量小于或等于当前最大ID,则此函数假定为ID/原生代币
  function transferFrom(
    address from,
    address to,
    uint256 amountOrId
  ) public virtual {
    if (amountOrId <= minted) {
      if (from != _ownerOf[amountOrId]) {
        revert InvalidSender();
      }

      if (to == address(0)) {
        revert InvalidRecipient();
      }

      if (
        msg.sender != from &&
        !isApprovedForAll[from][msg.sender] &&
        msg.sender != getApproved[amountOrId]
      ) {
        revert Unauthorized();
      }

      balanceOf[from] -= _getUnit();

      unchecked {
        balanceOf[to] += _getUnit();
      }

      _ownerOf[amountOrId] = to;
      delete getApproved[amountOrId];

      // 更新发送者的_owned
      uint256 updatedId = _owned[from][_owned[from].length - 1];
      _owned[from][_ownedIndex[amountOrId]] = updatedId;
      // 弹出
      _owned[from].pop();
      // 更新移动ID的索引
      _ownedIndex[updatedId] = _ownedIndex[amountOrId];
      // 将代币推送到接收者的owned
      _owned[to].push(amountOrId);
      // 更新接收者owned的索引
      _ownedIndex[amountOrId] = _owned[to].length - 1;

      emit Transfer(from, to, amountOrId);
      emit ERC20Transfer(from, to, _getUnit());
    } else {
      uint256 allowed = allowance[from][msg.sender];

      if (allowed != type(uint256).max)
        allowance[from][msg.sender] = allowed - amountOrId;

      _transfer(from, to, amountOrId);
    }
  }

  /// @notice 分数转账函数
  function transfer(address to, uint256 amount) public virtual returns (bool) {
    return _transfer(msg.sender, to, amount);
  }

  /// @notice 支持合约的原生转账函数
  function safeTransferFrom(
    address from,
    address to,
    uint256 id
  ) public virtual {
    transferFrom(from, to, id);

    if (
      to.code.length != 0 &&
      ERC721Receiver(to).onERC721Received(msg.sender, from, id, "") !=
      ERC721Receiver.onERC721Received.selector
    ) {
      revert UnsafeRecipient();
    }
  }

  /// @notice 支持合约的原生转账函数,带回调数据
  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    bytes calldata data
  ) public virtual {
    transferFrom(from, to, id);

    if (
      to.code.length != 0 &&
      ERC721Receiver(to).onERC721Received(msg.sender, from, id, data) !=
      ERC721Receiver.onERC721Received.selector
    ) {
      revert UnsafeRecipient();
    }
  }

  /// @notice 内部分数转账函数
  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal returns (bool) {
    uint256 unit = _getUnit();
    uint256 balanceBeforeSender = balanceOf[from];
    uint256 balanceBeforeReceiver = balanceOf[to];

    balanceOf[from] -= amount;

    unchecked {
      balanceOf[to] += amount;
    }

    // 对某些地址跳过销毁以节省gas
    if (!whitelist[from]) {
      uint256 tokens_to_burn = (balanceBeforeSender / unit) -
        (balanceOf[from] / unit);
      for (uint256 i = 0; i < tokens_to_burn; i++) {
        _burn(from);
      }
    }

    // 对某些地址跳过铸造以节省gas
    if (!whitelist[to]) {
      uint256 tokens_to_mint = (balanceOf[to] / unit) -
        (balanceBeforeReceiver / unit);
      for (uint256 i = 0; i < tokens_to_mint; i++) {
        _mint(to);
      }
    }

    emit ERC20Transfer(from, to, amount);
    return true;
  }

  // 内部工具逻辑
  function _getUnit() internal view returns (uint256) {
    return 10 ** decimals;
  }

  function _mint(address to) internal virtual {
    if (to == address(0)) {
      revert InvalidRecipient();
    }

    unchecked {
      minted++;
    }

    uint256 id = minted;

    if (_ownerOf[id] != address(0)) {
      revert AlreadyExists();
    }

    _ownerOf[id] = to;
    _owned[to].push(id);
    _ownedIndex[id] = _owned[to].length - 1;

    emit Transfer(address(0), to, id);
  }

  function _burn(address from) internal virtual {
    if (from == address(0)) {
      revert InvalidSender();
    }

    uint256 id = _owned[from][_owned[from].length - 1];
    _owned[from].pop();
    delete _ownedIndex[id];
    delete _ownerOf[id];
    delete getApproved[id];

    emit Transfer(from, address(0), id);
  }

  function _setNameSymbol(string memory _name, string memory _symbol) internal {
    name = _name;
    symbol = _symbol;
  }
}
