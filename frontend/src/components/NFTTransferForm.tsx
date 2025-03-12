import React, { useState } from 'react';
import { Send, Image } from 'lucide-react';

interface NFTTransferFormProps {
  onTransfer: (from: string, to: string, tokenId: string) => Promise<void>;
  onGetOwner: (tokenId: string) => Promise<string>;
}

export function NFTTransferForm({ onTransfer, onGetOwner }: NFTTransferFormProps) {
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [tokenId, setTokenId] = useState('');
  const [currentOwner, setCurrentOwner] = useState('');

  const handleCheckOwner = async () => {
    if (tokenId) {
      try {
        const owner = await onGetOwner(tokenId);
        setCurrentOwner(owner);
        setFrom(owner);
      } catch (error) {
        console.error('Failed to get owner:', error);
      }
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await onTransfer(from, to, tokenId);
      // Reset form
      setTo('');
      setTokenId('');
      setCurrentOwner('');
    } catch (error) {
      console.error('NFT transfer failed:', error);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="bg-white p-6 rounded-lg shadow-md mb-8">
      <div className="flex items-center gap-3 mb-6">
        <Image className="w-5 h-5 text-purple-500" />
        <h2 className="text-xl font-bold">NFT Transfer</h2>
      </div>

      <div className="mb-4">
        <label className="block text-sm font-medium mb-2">Token ID</label>
        <div className="flex gap-2">
          <input
            type="text"
            value={tokenId}
            onChange={(e) => setTokenId(e.target.value)}
            className="flex-1 p-2 border rounded-md"
            placeholder="Enter NFT Token ID"
            required
          />
          <button
            type="button"
            onClick={handleCheckOwner}
            className="px-4 py-2 bg-gray-100 text-gray-700 rounded-md hover:bg-gray-200 transition-colors"
          >
            Check Owner
          </button>
        </div>
      </div>

      {currentOwner && (
        <div className="mb-4 p-3 bg-gray-50 rounded-md">
          <p className="text-sm text-gray-600">Current Owner:</p>
          <p className="font-mono text-sm">{currentOwner}</p>
        </div>
      )}

      <div className="mb-4">
        <label className="block text-sm font-medium mb-2">To Address</label>
        <input
          type="text"
          value={to}
          onChange={(e) => setTo(e.target.value)}
          className="w-full p-2 border rounded-md"
          placeholder="Recipient Address (0x...)"
          required
        />
      </div>

      <button
        type="submit"
        className="w-full bg-purple-500 text-white py-2 px-4 rounded-md hover:bg-purple-600 transition-colors"
      >
        Transfer NFT
      </button>
    </form>
  );
}