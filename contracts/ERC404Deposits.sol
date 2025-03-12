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
    mapping(uint256 => TokenDeposit[]) public _tokenDeposits;

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
        depositTokens(tokenId_, address(this), amount_);
    }

    function depositTokens(uint256 tokenId_, address tokenAddress_, uint256 amount_) public virtual {}

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
//audit-issue
                IERC20(deposit.tokenAddress).transferFrom(from_, to_, deposit.amount);
                // 发出事件来追踪存款的转移
                // 实际代币仍然存在合约中，只是所有权随NFT转移
                emit TokensWithdrawn(tokenId_, deposit.tokenAddress, deposit.amount);
                emit TokensDeposited(tokenId_, deposit.tokenAddress, deposit.amount);
            }
        }
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