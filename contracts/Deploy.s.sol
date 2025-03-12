// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "../contracts/ERC404.sol";

contract DeployScript is Script {
    uint8 public constant DECIMALS = 18;
    uint256 public constant UNIT = 10 ** DECIMALS;
    function run() external returns(address){
        vm.startBroadcast();

        // 部署合约
        TestERC404 test1 = new TestERC404("Test Token", "TEST", DECIMALS);
        
        // 如果合约需要初始化，在这里调用初始化函数
        // yourContract.initialize(参数);

        vm.stopBroadcast();
        return address(test1);
    }
}

contract TestERC404 is ERC404 {
    
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC404(name_, symbol_, decimals_) {}

    // 实现必需的 tokenURI 函数
    function tokenURI(uint256) public pure override returns (string memory) {
        return "test-uri";
    }

    // 添加公共铸造函数用于测试
    function mint(address to, uint256 value) public {
        _mintERC20(to, value);
    }
}