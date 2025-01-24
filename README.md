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
[点击查看详细接口文档](interface.md)
### 1. ERC20与ERC721混合转账机制
合约通过_isValidTokenId函数来区分转账类型，而不是通过不同的接口。当用户调用transferFrom时，系统首先检查valueOrId是否为有效的NFT ID。如果返回true，则执行NFT转移逻辑；如果返回false，则执行代币转移逻辑。这种设计使得同一个函数可以智能地处理两种不同类型的转账操作，简化了用户交互流程。

### 2. 代币注入系统
合约提供了灵活的代币注入功能。用户可以选择将持有的代币注入指定的NFT中。注入过程包括多个安全检查：首先验证用户的代币余额是否充足，然后更新目标NFT的元数据信息。完成注入后，系统会自动销毁相应数量的原始NFT，并将注入的代币锁定在合约中。这个机制让用户能够灵活管理资产价值分布。

### 3. NFT铸造豁免控制
系统设计了完整的豁免控制机制。用户可以自主选择是否参与自动NFT铸造。豁免状态通过智能合约的状态变量进行管理，使用映射结构存储每个地址的具体豁免设置。这提供了资产管理的灵活性，特别适合需要频繁进行代币操作的场景。

### 4. 价值递增保护
合约实现了强大的价值保护机制。系统会持续追踪每个NFT的历史最高注入量。当NFT被销毁并提取其中的代币时，系统会永久记录该NFT ID对应的最低代币要求。这确保了同一ID的NFT在重新铸造时必须满足或超过之前的价值水平，有效防止价值稀释。

### 5. 资产管理优化
系统通过智能的数据结构设计优化了资产管理效率。使用映射和数组的组合存储方式，实现了快速的资产查询和更新。合约还包含了完整的事件系统，记录所有重要操作，便于链下应用进行数据同步和分析。



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

### 1. 社区治理与升级机制
引入基于NFT持有量的投票权重机制，持有PAN数量越多的NFT在提案投票中权重越大。同时实现可升级合约设计，确保系统可以安全地进行功能更新和漏洞修复。

### 2. 跨链互操作与流动性优化
实现跨链桥接功能，让用户可以在不同公链上转移和使用PAN-NFT。开发批量操作功能，允许用户一次性处理多个NFT，提高操作效率并降低gas费用。

### 3. 智能价值管理
开发智能价值管理系统，包括自动化的价值分配、NFT合并拆分等功能。系统可以根据市场情况和用户需求，灵活调整NFT的价值分布，优化资产配置效率。

### 4. 有趣的荷兰拍卖
荷兰拍卖是一种从高价开始逐步降低的拍卖形式。在我们的系统中，卖家可以设置NFT的起拍价格和最低价格，以及价格下降的速度。当买家觉得当前价格合适时可以直接购买。这种机制的独特之处在于:

- 卖家可以通过注入PAN代币来设置NFT的最低价格保护
- 价格下降曲线支持线性和指数两种模式
- 买家可以提前锁定心仪的NFT，并设置自动购买价格
- 拍卖结束后，系统自动处理PAN代币的转移和NFT所有权变更
- 支持批量拍卖功能，卖家可以同时拍卖多个具有相同属性的NFT

这种拍卖机制既保护了卖家利益，又为买家提供了灵活的购买选择，同时通过PAN代币注入确保了NFT的最低价值。



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
