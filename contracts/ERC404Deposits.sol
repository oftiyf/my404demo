// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract ERC404Deposits {
    /// @dev 每个NFT的存款信息结构
    struct TokenDeposit {
        address tokenAddress;  // ERC20代币地址
        uint256 amount;       // 存入数量
    }
    mapping(uint256 => TokenDeposit[]) internal _splitDeposits;


    /// @dev NFT ID => 代币存款数组的映射
    /// @dev 数组索引0位置存储原生ERC20资产，其他位置预留给未来可能的扩展
    mapping(uint256 => TokenDeposit[]) internal _tokenDeposits;

    /// @dev NFT ID => 所需的最小ERC20数量
    /// @dev 当NFT被拆分时，记录其中注入的资产数量，任何人凑够这个数量都可以获得该ID
    mapping(uint256 => uint256) internal _requiredAmount;
    /// @dev 事件定义
    event TokensDeposited(uint256 indexed tokenId, address indexed tokenAddress, uint256 amount);
    event TokensWithdrawn(uint256 indexed tokenId, address indexed tokenAddress, uint256 amount);

    /// @notice 向指定的NFT存入本合约的ERC20代币
    /// @param tokenId_ NFT的ID
    /// @param amount_ 存入的数量
    function depositTokens(uint256 tokenId_, uint256 amount_) public virtual {
        // 验证NFT存在且调用者是所有者
        require(_isOwner(msg.sender, tokenId_), "Not token owner");
        require(amount_ > 0, "Amount must be greater than 0");

        // 如果是首次存款，初始化数组并添加第一个元素
        if (_tokenDeposits[tokenId_].length == 0) {
            _tokenDeposits[tokenId_].push(TokenDeposit({
                tokenAddress: address(this),  // 原生ERC20代币地址
                amount: amount_
            }));
        } else {
            // 如果已经有存款，直接累加到索引0位置
            _tokenDeposits[tokenId_][0].amount += amount_;
        }

        // 处理代币转账（从用户转到合约）
        require(_transferFromSender(msg.sender, address(this), amount_), "Transfer failed");

        emit TokensDeposited(tokenId_, address(this), amount_);
    }

    /// @notice 获取指定NFT的所有存款信息
    /// @param tokenId_ NFT的ID
    function getTokenDeposits(uint256 tokenId_) public view virtual returns (TokenDeposit[] memory) {
        return _tokenDeposits[tokenId_];
    }

    /// @notice 在NFT转移时转移所有存款
    /// @dev 这个函数应该在NFT转移时被调用
    function _transferDeposits(uint256 tokenId_, address from_, address to_) internal virtual {
        TokenDeposit[] storage deposits = _tokenDeposits[tokenId_];
        uint256 depositCount = deposits.length;
        
        if (depositCount > 0) {
            for (uint256 i = 0; i < depositCount; i++) {
                TokenDeposit storage deposit = deposits[i];
                
                // 发出事件来追踪存款的转移
                // 实际代币仍然存在合约中，只是所有权随NFT转移
                emit TokensWithdrawn(tokenId_, deposit.tokenAddress, deposit.amount);
                emit TokensDeposited(tokenId_, deposit.tokenAddress, deposit.amount);
            }
        }
    }

    /// @notice 从NFT中提取特定代币
    /// @param tokenId_ NFT的ID
    /// @param depositIndex_ 要提取的存款索引
    function withdrawTokens(uint256 tokenId_, uint256 depositIndex_) public virtual {
        // 验证NFT存在且调用者是所有者
        require(_isOwner(msg.sender, tokenId_), "Not token owner");
        require(depositIndex_ < _tokenDeposits[tokenId_].length, "Invalid deposit index");

        // 获取存款信息
        TokenDeposit storage deposit = _tokenDeposits[tokenId_][depositIndex_];
        uint256 amount = deposit.amount;
        address tokenAddress = deposit.tokenAddress;

        // 在转账前移除存款记录（防止重入攻击）
        _removeDeposit(tokenId_, depositIndex_);

        // 转移代币
        if (tokenAddress == address(this)) {
            // 如果是本合约代币
            require(_transfer(address(this), msg.sender, amount), "Transfer failed");
        } else {
            // 如果是其他ERC20代币
            IERC20 token = IERC20(tokenAddress);
            require(token.transfer(msg.sender, amount), "Transfer failed");
        }

        emit TokensWithdrawn(tokenId_, tokenAddress, amount);
    }

    /// @notice 移除指定索引的存款记录
    function _removeDeposit(uint256 tokenId_, uint256 index_) internal virtual {
        TokenDeposit[] storage deposits = _tokenDeposits[tokenId_];
        require(index_ < deposits.length, "Invalid index");
        
        // 将最后一个元素移到要删除的位置，然后删除最后一个元素
        if (index_ != deposits.length - 1) {
            deposits[index_] = deposits[deposits.length - 1];
        }
        deposits.pop();
    }

    /// @dev 这些函数需要被继承合约实现
    function _isOwner(address owner_, uint256 tokenId_) internal virtual returns (bool);
    function _transfer(address from_, address to_, uint256 amount_) internal virtual returns (bool);
    function _transferFromSender(address from_, address to_, uint256 amount_) internal virtual returns (bool);

    /// @notice 在NFT被拆分时记录所需的最小数量
    function _handleNFTSplit(uint256 tokenId_) internal {
        if (_tokenDeposits[tokenId_].length > 0) {
            // 记录所需的最小数量（向下取整）
            _requiredAmount[tokenId_] = _tokenDeposits[tokenId_][0].amount;
            
            // 清除当前存款记录
            delete _tokenDeposits[tokenId_];
        }
    }

    /// @notice 检查是否可以恢复特定ID的NFT
    /// @dev 任何人只要有足够的代币都可以获得这个ID
    function _canRestoreNFT(uint256 tokenId_)  internal view virtual returns (bool) {
        uint256 requiredAmount = _requiredAmount[tokenId_];
        if (requiredAmount == 0) {
            return true; // 如果没有要求的数量，可以直接恢复
        }

        // 检查当前存款是否满足要求
        TokenDeposit[] storage currentDeposits = _tokenDeposits[tokenId_];
        if (currentDeposits.length == 0) return false;
        
        return currentDeposits[0].amount >= requiredAmount;
    }

    /// @notice 在NFT被恢复时处理记录
    function _handleNFTRestore(uint256 tokenId_) internal virtual {
        uint256 requiredAmount = _requiredAmount[tokenId_];
        if (requiredAmount > 0) {
            require(_canRestoreNFT(tokenId_), "Insufficient deposits to restore NFT");
            
            // 清除要求记录
            delete _requiredAmount[tokenId_];
        }
    }
} 