import React, { useEffect, useState } from 'react';
import { ethers } from 'ethers';
import { TokenInfo } from './components/TokenInfo';
import { TransactionForm } from './components/TransactionForm';
import { NFTTransferForm } from './components/NFTTransferForm';
import { Coins } from 'lucide-react';

const CONTRACT_ADDRESS = '0x285B1F4AEE4695AcE58307f4bdbaD41417661e50';
//这个地方放入合约地址

function App() {
  const [provider, setProvider] = useState<ethers.providers.Web3Provider | null>(null);
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  const [account, setAccount] = useState<string>('');
  const [balance, setBalance] = useState("0");
  const [erc20Balance, setErc20Balance] = useState("0");
  const [erc721Balance, setErc721Balance] = useState("0");
  const [totalSupply, setTotalSupply] = useState("0");
  const [symbol, setSymbol] = useState("");

  // 将 mockContract 移到组件内部
  const mockContract = {
    // Token Functions
    balanceOf: async () => "1000",
    erc20BalanceOf: async () => "800",
    erc721BalanceOf: async () => "200",
    totalSupply: async () => "1000000",
    erc20TotalSupply: async () => "800000",
    erc721TotalSupply: async () => "200000",
    symbol: async () => "TKN",
    
    transfer: async (to: string, amount: string) => {
      try {
        console.log(`Transfer ${amount} to ${to}`);
        if (!to) throw new Error("InvalidRecipient");
        if (parseInt(amount) <= 0) throw new Error("InvalidAmount");
      } catch (error) {
        console.error("Transfer failed:", error);
        throw error;
      }
    },

    erc721TransferFrom: async (from: string, to: string, tokenId: string) => {
      try {
        console.log(`Transfer NFT ${tokenId} from ${from} to ${to}`);
        if (!to) throw new Error("InvalidRecipient");
        if (!tokenId) throw new Error("InvalidTokenId");
      } catch (error) {
        console.error("NFT transfer failed:", error);
        throw error;
      }
    },
    
    ownerOf: async (tokenId: string) => {
      if (!tokenId) throw new Error("InvalidTokenId");
      return "0x1234...";
    },

    erc721TransferExempt: async (account: string) => {
      return false;
    },
  };

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [
          balanceResult,
          erc20BalanceResult,
          erc721BalanceResult,
          supplyResult,
          symbolResult
        ] = await Promise.all([
          mockContract.balanceOf(),
          mockContract.erc20BalanceOf(),
          mockContract.erc721BalanceOf(),
          mockContract.totalSupply(),
          mockContract.symbol()
        ]);

        setBalance(balanceResult);
        setErc20Balance(erc20BalanceResult);
        setErc721Balance(erc721BalanceResult);
        setTotalSupply(supplyResult);
        setSymbol(symbolResult);
      } catch (error) {
        console.error("Failed to fetch token data:", error);
      }
    };

    fetchData();
  }, []);

  // 连接钱包
  const connectWallet = async () => {
    try {
      if (window.ethereum) {
        const web3Provider = new ethers.providers.Web3Provider(window.ethereum);
        await web3Provider.send("eth_requestAccounts", []);
        const signer = web3Provider.getSigner();
        const address = await signer.getAddress();
        
        setProvider(web3Provider);
        setSigner(signer);
        setAccount(address);
      } else {
        alert('请安装 MetaMask!');
      }
    } catch (error) {
      console.error('连接钱包失败:', error);
    }
  };

  // 修改合约调用方式
  const contract = {
    // Token Functions
    balanceOf: async () => {
      if (!signer || !CONTRACT_ADDRESS) return "0";
      const contract = new ethers.Contract(CONTRACT_ADDRESS, ['function balanceOf(address) view returns (uint256)'], signer);
      return await contract.balanceOf(account);
    },
    
    transfer: async (to: string, amount: string) => {
      if (!signer || !CONTRACT_ADDRESS) throw new Error("未连接钱包");
      const contract = new ethers.Contract(CONTRACT_ADDRESS, ['function transfer(address, uint256) returns (bool)'], signer);
      const tx = await contract.transfer(to, amount);
      await tx.wait();
    },
    
    // NFT 相关
    erc721TransferFrom: async (from: string, to: string, tokenId: string) => {
      try {
        console.log(`Transfer NFT ${tokenId} from ${from} to ${to}`);
        // 模拟检查
        if (!to) throw new Error("InvalidRecipient");
        if (!tokenId) throw new Error("InvalidTokenId");
      } catch (error) {
        console.error("NFT transfer failed:", error);
        throw error;
      }
    },
    
    ownerOf: async (tokenId: string) => {
      if (!tokenId) throw new Error("InvalidTokenId");
      return "0x1234...";
    },

    // 添加其他必要的接口
    erc721TransferExempt: async (account: string) => {
      return false;
    },
  };

  return (
    <div className="min-h-screen bg-gray-100 p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div className="flex items-center gap-3">
            <Coins className="w-8 h-8 text-blue-500" />
            <h1 className="text-3xl font-bold">Token Dashboard</h1>
          </div>
          <button
            onClick={connectWallet}
            className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
          >
            {account ? `${account.slice(0, 6)}...${account.slice(-4)}` : '连接钱包'}
          </button>
        </div>

        <TokenInfo
          balance={balance}
          totalSupply={totalSupply}
          symbol={symbol}
        />

        <TransactionForm
          onTransfer={mockContract.transfer}
          onDeposit={mockContract.depositTokens}
          onWithdraw={mockContract.withdrawTokens}
        />

        <NFTTransferForm
          onTransfer={mockContract.erc721TransferFrom}
          onGetOwner={mockContract.ownerOf}
        />
      </div>
    </div>
  );
}

export default App;