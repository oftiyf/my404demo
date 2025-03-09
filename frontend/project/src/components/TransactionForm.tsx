import React, { useState } from 'react';
import { Send } from 'lucide-react';

interface TransactionFormProps {
  onTransfer: (to: string, amount: string) => Promise<void>;
  onDeposit: (id: string, amount: string) => Promise<void>;
  onWithdraw: (amount: string) => Promise<void>;
}

export function TransactionForm({ onTransfer, onDeposit, onWithdraw }: TransactionFormProps) {
  const [action, setAction] = useState<'transfer' | 'deposit' | 'withdraw'>('transfer');
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [id, setId] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      switch (action) {
        case 'transfer':
          await onTransfer(to, amount);
          break;
        case 'deposit':
          await onDeposit(id, amount);
          break;
        case 'withdraw':
          await onWithdraw(amount);
          break;
      }
      // Reset form
      setTo('');
      setAmount('');
      setId('');
    } catch (error) {
      console.error('Transaction failed:', error);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="bg-white p-6 rounded-lg shadow-md mb-8">
      <div className="flex items-center gap-3 mb-6">
        <Send className="w-5 h-5 text-blue-500" />
        <h2 className="text-xl font-bold">Token Transaction</h2>
      </div>

      <div className="mb-4">
        <select
          className="w-full p-2 border rounded-md"
          value={action}
          onChange={(e) => setAction(e.target.value as any)}
        >
          <option value="transfer">Transfer</option>
          <option value="deposit">Deposit</option>
          <option value="withdraw">Withdraw</option>
        </select>
      </div>

      {action === 'transfer' && (
        <div className="mb-4">
          <label className="block text-sm font-medium mb-2">To Address</label>
          <input
            type="text"
            value={to}
            onChange={(e) => setTo(e.target.value)}
            className="w-full p-2 border rounded-md"
            placeholder="0x..."
            required
          />
        </div>
      )}

      {action === 'deposit' && (
        <div className="mb-4">
          <label className="block text-sm font-medium mb-2">Token ID</label>
          <input
            type="text"
            value={id}
            onChange={(e) => setId(e.target.value)}
            className="w-full p-2 border rounded-md"
            placeholder="Token ID"
            required
          />
        </div>
      )}

      <div className="mb-4">
        <label className="block text-sm font-medium mb-2">Amount</label>
        <input
          type="text"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full p-2 border rounded-md"
          placeholder="0.0"
          required
        />
      </div>

      <button
        type="submit"
        className="w-full bg-blue-500 text-white py-2 px-4 rounded-md hover:bg-blue-600 transition-colors"
      >
        {action.charAt(0).toUpperCase() + action.slice(1)}
      </button>
    </form>
  );
}