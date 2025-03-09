import React from 'react';
import { CircleDollarSign, Coins, Wallet } from 'lucide-react';

interface TokenInfoProps {
  balance: string;
  symbol: string;
  totalSupply: string;
}

export function TokenInfo({ balance, symbol, totalSupply }: TokenInfoProps) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
      <div className="bg-white p-6 rounded-lg shadow-md">
        <div className="flex items-center gap-3 mb-2">
          <Wallet className="w-5 h-5 text-blue-500" />
          <h3 className="text-lg font-semibold">Balance</h3>
        </div>
        <p className="text-2xl font-bold">{balance} {symbol}</p>
      </div>
      
      <div className="bg-white p-6 rounded-lg shadow-md">
        <div className="flex items-center gap-3 mb-2">
          <Coins className="w-5 h-5 text-green-500" />
          <h3 className="text-lg font-semibold">Total Supply</h3>
        </div>
        <p className="text-2xl font-bold">{totalSupply} {symbol}</p>
      </div>

      <div className="bg-white p-6 rounded-lg shadow-md">
        <div className="flex items-center gap-3 mb-2">
          <CircleDollarSign className="w-5 h-5 text-purple-500" />
          <h3 className="text-lg font-semibold">Token Symbol</h3>
        </div>
        <p className="text-2xl font-bold">{symbol}</p>
      </div>
    </div>
  );
}