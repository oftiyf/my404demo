// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

/**
 * @title ERC721Events
 * @dev Library containing all events emitted by ERC721 tokens
 */
library ERC721Events {
  /**
   * @dev Emitted when `owner` enables or disables `operator` to manage all of their tokens
   * @param owner The address granting/revoking approval for all tokens
   * @param operator The address receiving/losing approval to manage all tokens
   * @param approved True if approving, false if revoking approval
   */
  event ApprovalForAll(
    address indexed owner,
    address indexed operator,
    bool approved
  );

  /**
   * @dev Emitted when `owner` approves `spender` to manage a specific token
   * @param owner The address granting approval
   * @param spender The address receiving approval
   * @param id The ID of the token being approved
   */
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 indexed id
  );

  /**
   * @dev Emitted when a token is transferred from one address to another
   * @param from The address sending the token
   * @param to The address receiving the token
   * @param id The ID of the token being transferred
   */
  event Transfer(address indexed from, address indexed to, uint256 indexed id);
}
