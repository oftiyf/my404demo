// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ERC404.sol";

// 创建一个简单的 ERC404 实现用于测试
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

contract ERC404Test is Test {
    TestERC404 public token;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    uint8 public constant DECIMALS = 18;
    uint256 public constant UNIT = 10 ** DECIMALS;

    function setUp() public {
        // 部署测试合约
        token = new TestERC404("Test Token", "TEST", DECIMALS);
        
        // 给测试账户一些 ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testInitialSetup() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.units(), UNIT);
    }

    function testMinting() public {
        // 铸造 1 个完整单位的代币
        token.mint(alice, UNIT);
        
        // 检查 ERC20 余额
        assertEq(token.erc20BalanceOf(alice), UNIT);
        
        // 检查 ERC721 余额
        assertEq(token.erc721BalanceOf(alice), 1);
        
        // 检查总供应量
        assertEq(token.totalSupply(), UNIT);
        assertEq(token.erc721TotalSupply(), 1);
    }

    function testTransfer() public {
        // 先铸造一些代币给 Alice
        token.mint(alice, UNIT);
        
        // 切换到 Alice 的视角
        vm.startPrank(alice);
        
        // 转移 1 个完整单位的代币给 Bob
        token.transfer(bob, UNIT);
        
        vm.stopPrank();

        // 验证余额变化
        assertEq(token.erc20BalanceOf(alice), 0);
        assertEq(token.erc20BalanceOf(bob), UNIT);
        assertEq(token.erc721BalanceOf(alice), 0);
        assertEq(token.erc721BalanceOf(bob), 1);
    }

    function testPartialTransfer() public {
        // 铸造 2 个完整单位的代币给 Alice
        token.mint(alice, 2 * UNIT);
        
        vm.startPrank(alice);
        
        // 转移 1.5 个单位的代币给 Bob
        token.transfer(bob, 3 * UNIT/2);
        
        vm.stopPrank();

        // 验证 ERC20 余额
        assertEq(token.erc20BalanceOf(alice), 1 * UNIT/2);
        assertEq(token.erc20BalanceOf(bob), 3 * UNIT/2);
        
        // 验证 ERC721 余额（应该只转移了 1 个 NFT）
        assertEq(token.erc721BalanceOf(alice), 0);
        assertEq(token.erc721BalanceOf(bob), 1);
    }

    function testApproveAndTransferFrom() public {
        token.mint(alice, UNIT);
        
        vm.startPrank(alice);
        // Alice 授权 Bob 使用她的代币
        token.approve(bob, UNIT);
        vm.stopPrank();

        vm.startPrank(bob);
        // Bob 从 Alice 那里转移代币
        token.transferFrom(alice, bob, UNIT);
        vm.stopPrank();

        // 验证余额
        assertEq(token.erc20BalanceOf(alice), 0);
        assertEq(token.erc20BalanceOf(bob), UNIT);
    }

    function testERC721TransferExempt() public {
        // 将 Bob 设置为 ERC721 转账豁免地址
        token.setSelfERC721TransferExempt(true);
        
        token.mint(alice, UNIT);
        
        vm.startPrank(alice);
        // 应该能够转移 ERC20，但不会转移 ERC721
        token.transfer(bob, UNIT);
        vm.stopPrank();

        // Bob 不应该收到 NFT
        assertEq(token.erc721BalanceOf(bob), 0);
        // 但应该收到 ERC20 代币
        assertEq(token.erc20BalanceOf(bob), UNIT);
    }

    function testFailMintOverflow() public {
        // 尝试铸造超过最大供应量的代币
        token.mint(alice, token.ID_ENCODING_PREFIX());
    }

    function testFailInvalidTransfer() public {
        token.mint(alice, UNIT);
        
        vm.startPrank(alice);
        // 尝试转移超过余额的金额
        token.transfer(bob, 2 * UNIT);
        vm.stopPrank();
    }
}