
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
