// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ERC404.sol";
import {ERC404Deposits} from "../contracts/ERC404Deposits.sol";  // 导入整个合约
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

    struct TokenDeposit {
        address tokenAddress;
        uint256 amount;
    }

    event ApprovalFailed(string message);
    event ApprovalSuccess(string message);
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
        token.mint(alice, 2*UNIT);
        
        // 检查 ERC20 余额
        assertEq(token.erc20BalanceOf(alice), 2*UNIT);
        
    }

    function testTransferandApprove() public {
        // 先铸造一些代币给 Alice
        token.mint(alice, 10*UNIT);

        // 切换到 Alice 的视角
        vm.startPrank(alice);

        //这里用try catch测试一下approve
        try token.approve(bob, UNIT) {
            emit ApprovalSuccess("approve success");
        } catch (bytes memory) {
            emit ApprovalFailed("approve failed");
        }


        vm.stopPrank();

        vm.startPrank(bob);
        
        token.transferFrom(alice, bob, UNIT);
        //查看一下_storedERC721Ids 具体内容
        uint256[] memory aliceNFTs = token.owned(alice);
        console.log("Alice's NFT IDs:");
        for(uint256 i = 0; i < aliceNFTs.length; i++) {
            console.log("NFT #", i, ":", aliceNFTs[i]);
        }

        if (aliceNFTs.length > 0) {
        ERC404Deposits.TokenDeposit[] memory deposits = token.getTokenDeposits(aliceNFTs[0]);  
        console.log("Alice's deposits for NFT", aliceNFTs[0], ":");
        for(uint256 i = 0; i < deposits.length; i++) {
            console.log("Deposit #1233", i, "amount:", deposits[i].amount);
            console.log("Deposit #", i, "token:", deposits[i].tokenAddress);
        }
        //@audit 我没有默认存储，所以返回了0
        console.log("Alice's deposits length:", deposits.length);   
    } else {
        console.log("Alice has no NFTs");
    }
        vm.stopPrank();
    }

    function testWithdrawAndStoreERC721() public {
        token.mint(alice, 10*UNIT);
        vm.startPrank(alice);
        //获取某个nftid
        uint256[] memory aliceNFTs = token.owned(alice);
        console.log("Alice's NFT ID for deposit:");
        for(uint256 i = 0; i < aliceNFTs.length; i++) {
            console.log("NFT #", i, ":", aliceNFTs[i]);
        }

        token.depositTokens(aliceNFTs[0], address(token), 9*UNIT);
        //查看自己的余额，用console.log
        console.log("Alice's balanceafter!!!:", token.balanceOf(alice));
        uint256[] memory aliceNFTsafter = token.owned(alice);
        console.log("Alice's NFT ID for deposit after!!!:");
        for(uint256 i = 0; i < aliceNFTsafter.length; i++) {
            console.log("NFT #", i, ":", aliceNFTsafter[i]);
        }
    }
}
