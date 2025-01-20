# PAN Protocol

## 项目简介

PAN Protocol 是一个创新性的 NFT 金融协议，它通过独特的同质化代币(PAN)与非同质化代币(NFT)绑定机制，从根本上解决了 NFT 在 DeFi 领域面临的核心问题。

### 核心价值主张
- **流动性增强**：通过将 NFT 与 PAN 代币绑定，使 NFT 在保持其独特性的同时获得类似同质化代币的流动性特征。
- **清算难题解决**：当 NFT 被用作抵押品时，清算方可以直接通过清算其绑定的 PAN 代币来完成清算流程，避免了传统 NFT 清算中的定价和流动性问题。
- **价值维护**：采用创新的"注入"机制和价值递增设计，确保 NFT 在交易过程中保持并提升其价值，打造真正的数字资产。

### 运作机制
1. **自动绑定**：用户持有的每1个 PAN 代币都会自动对应1个 NFT，实现无缝资产映射。
2. **价值注入**：用户可以将多个 PAN 代币注入到单个 NFT 中，提升该 NFT 的内在价值。
3. **价值锁定**：一旦 NFT 被"打破"（即其绑定的 PAN 被提取），后续重新铸造该 NFT 将需要更多的 PAN 代币，确保价值持续上升。

### 创新亮点
- 首创同质化代币与非同质化代币的智能绑定机制
- 解决了 NFT 在 DeFi 领域的清算难题
- 实现了 NFT 价值的可度量性和可追溯性
- 保持了 NFT 的稀缺性和收藏价值

### 应用前景
该协议为 NFT 在 DeFi 领域的广泛应用铺平了道路，特别适用于：
- NFT 抵押借贷
- 数字艺术品价值存储
- 链上资产流动性管理
- 去中心化金融创新



## 核心功能

### 1. PAN代币与NFT自动绑定
合约监听所有PAN代币的转账事件。当用户A向用户B转账100个PAN时，智能合约的_beforeTokenTransfer钩子函数被触发。系统首先检查用户B是否开启了721豁免，若未豁免，则为用户B铸造100个NFT，NFT的ID从上次铸造结束的位置开始递增。每个NFT的metadata中都记录了与其绑定的PAN代币数量。

### 2. NFT注入机制
用户通过合约的inject函数进行PAN注入。例如用户想将9个PAN注入到tokenId为100的NFT中，合约先检查用户的PAN余额是否足够，然后更新该NFT的metadata，将绑定的PAN数量从1个更新为10个。接着合约销毁用户持有的9个NFT(tokenId 101-109)，并将用户的9个PAN代币转入合约地址锁定。

### 3. 721豁免功能
合约提供setExempt函数控制NFT的自动铸造。用户或其授权地址可以调用该函数开启或关闭自动铸造功能。豁免状态被记录在合约的状态变量中，用mapping(address => bool)存储每个地址的豁免状态。

### 4. NFT价值递增
合约通过状态变量记录每个NFT最后注入的PAN数量。当NFT被打破(提取PAN)时，合约会在mapping中记录该tokenId对应的最低PAN要求。如tokenId 100的NFT包含10个PAN被打破，则该ID将永久要求至少10个PAN才能重新铸造，确保价值不会降低。


## 应用场景

### 1. NFT抵押借贷
用户Alice持有一个注入了100 PAN的NFT，她可以将这个NFT抵押给借贷协议。借贷协议可以准确计算抵押品价值(100 PAN)，并提供相应的借贷额度。如果Alice无法按时还款，协议可以直接清算NFT中的PAN代币，避免了传统NFT清算的流动性问题。

### 2. NFT价值存储
艺术家Bob发行限量版NFT作品，通过持续注入PAN来提升作品价值。当作品升值时，Bob可以继续注入PAN以维持作品的稀缺性和价值。收藏者购买时能清晰知道作品包含的具体价值量。

### 3. 游戏资产整合
游戏玩家Carol在游戏中获得了大量低价值NFT道具。她可以通过注入机制将多个低价值NFT合并成一个高价值NFT，简化资产管理并提升单个NFT的价值含量。

### 4. 社交身份凭证
社区成员Dave通过持续注入PAN到个人身份NFT中，展示其社区贡献度。贡献越多，注入越多，身份等级随之提升。这个NFT同时也代表了Dave在社区中的话语权重。

### 5. 交易市场定价
由于每个NFT都有明确的PAN含量，交易市场可以基于PAN数量设置最低定价标准。这让NFT价格更加透明，降低了虚假交易和价格操纵的可能性。


## 计划中的功能

### 1. 批量注入系统
开发批量PAN代币注入功能，允许用户一次性将多个PAN注入到不同NFT中。系统自动计算最优注入路径，降低gas费用，提高操作效率。

### 2. NFT分割机制
允许用户将高价值NFT拆分成多个低价值NFT。例如将包含100 PAN的NFT拆分成10个包含10 PAN的NFT，增加流动性和灵活性。

### 3. 社区治理系统
引入基于NFT持有量的投票权重机制。持有PAN数量越多的NFT，在提案投票中的权重越大，让社区决策更加去中心化。

### 4. 多链互操作
实现跨链桥接功能，让用户可以在不同公链上转移和使用PAN-NFT，扩大生态系统覆盖范围，提升用户体验。

### 5. 智能合约升级机制
引入可升级合约设计，确保系统可以安全地进行功能更新和漏洞修复，同时保持用户资产安全性。


## 测试方式

### 1. 开发环境准备
```bash
curl -L https://foundry.paradigm.xyz | bash   # 安装Foundryup
foundryup   # 安装最新版本Foundry
git clone https://github.com/xxx/pan-nft.git  # 克隆项目
cd pan-nft
forge install   # 安装依赖
```

### 2. 测试脚本编写
在`test`目录下创建测试文件`PanNFT.t.sol`:


### 3. 运行测试
```bash
forge test   # 运行所有测试
```






## Known Issues

1. Test Failures
- 5 tests failing with InvalidAmount() error:
  - testApproveAndTransferFrom()
  - testERC721TransferExempt()
  - testMinting()
  - testPartialTransfer()
  - testTransfer()
- Issues likely related to incorrect amount validation logic or calculation methods

2. Random Number Generation
- Lack of secure random number generation mechanism
- Current implementation needs improvement for better randomness

3. Gas Optimization
- High gas consumption in search operations
- Need to optimize lookup methods to reduce gas costs

4. Token Amount Handling
- Invalid amount errors occurring during token operations
- Amount validation and calculation logic needs review
