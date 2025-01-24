# 合约接口

# 常用接口

## 基础信息
- `name()`: 
- `symbol()`: 
- `decimals()`: 
- `totalSupply()`: 
- `units()`: 

## 账户相关
- `balanceOf(address)`: 查看的是对应的erc20资产
- `ownerOf(uint256)`: 内部填写对应的721id
- `owned(address)`: 查看某个地址拥有的721资产列表

## 转账相关
- `transfer(address,uint256)`:  这个默认是20的转账
- `transferFrom(address,address,uint256)`: 不鼓励使用这个，已经非管理员禁用了
- `safeTransferFrom(address,address,uint256)`: 这个是给非合约账户的接口，转账对应的erc20代币，同样可能作用于721资产
- `safeTransferFrom(address,address,uint256,bytes)`: 这个是给合约账户的接口，需要实现721回调函数的值

## 授权相关
- `approve(address,uint256)`:  授权对应的erc20代币
- `allowance(address,address)`:  查看授权额度
- `getApproved(uint256)`:  查看对应的721资产的授权
- `setApprovalForAll(address,bool)`:  授权对应的721资产
- `isApprovedForAll(address,address)`:  查看授权额度
- `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`:  授权对应的erc20代币

## 代币操作
- `depositTokens(uint256,address,uint256)`:  这个用于给721资产注入对应的erc20资产，现在仅支持原生erc20代币
- `depositTokens(uint256,uint256)`: 这个给用户端使用，直接调用上面那个函数，默认注入原生erc20代币
- `withdrawTokens(uint256 tokenId_)`:  打破的操作，将一个721资产打破为多个代币（还是可能诞生新的721资产）

## ERC721相关
- `erc721Approve(address,uint256)`:  721的对应转账许可
- `erc721BalanceOf(address)`:  721的对应余额
- `erc721TotalSupply()`:  721的对应总量
- `erc721TransferExempt(address)`:  721的对应转账豁免，**注意**该操作会导致已经存在的721资产被销毁
- `erc721TransferFrom(address,address,uint256)`:  721的对应转账
- `getERC721QueueLength()`:  721的对应队列长度
- `getERC721TokensInQueue(uint256,uint256)`:  721的对应队列中的资产
- `setSelfERC721TransferExempt(bool)`:  721的对应转账豁免，**注意**该操作会导致已经存在的721资产被销毁

# 不常用接口

## 系统参数
- `DOMAIN_SEPARATOR()`: 
- `ID_ENCODING_PREFIX()`: 
- `_tokenDeposits(uint256,uint256)`: 
- `getTokenDeposits(uint256)`: 
- `minted()`: 

## ERC20相关
- `erc20BalanceOf(address)`: 
- `erc20TotalSupply()`: 
- `erc20TransferFrom(address,address,uint256)`: 



## 其他
- `supportsInterface(bytes4)`: 
- `tokenURI(uint256)`: 
- `trygetmorevalue(uint256)`: 
