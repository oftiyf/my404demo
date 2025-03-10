export interface ContractFunctions {
  // ERC20 Functions
  balanceOf: (address: string) => Promise<string>;
  totalSupply: () => Promise<string>;
  transfer: (to: string, amount: string) => Promise<void>;
  approve: (spender: string, amount: string) => Promise<void>;
  depositTokens: (id: string, amount: string) => Promise<void>;
  withdrawTokens: (amount: string) => Promise<void>;
  name: () => Promise<string>;
  symbol: () => Promise<string>;
  decimals: () => Promise<number>;

  // ERC721 (NFT) Functions
  erc721BalanceOf: (address: string) => Promise<string>;
  erc721TransferFrom: (from: string, to: string, tokenId: string) => Promise<void>;
  ownerOf: (tokenId: string) => Promise<string>;
  getApproved: (tokenId: string) => Promise<string>;
  tokenURI: (tokenId: string) => Promise<string>;
}