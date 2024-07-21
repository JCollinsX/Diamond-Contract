# EIP-2535 Diamonds Implementation

This is a simple example implementation for [EIP-2535 Diamonds](https://eips.ethereum.org/EIPS/eip-2535). To learn about other implementations go here: https://github.com/mudgen/diamond

The standard loupe functions have been gas-optimized in this implementation and can be called in on-chain transactions. However keep in mind that a diamond can have any number of functions and facets so it is still possible to get out-of-gas errors when calling loupe functions. Except for the `facetAddress` loupe function which has a fixed gas cost.

The `contracts/facets/LaunchPadProjectFacet.sol` file shows an launchpad contract with Diamond implementation.

The `contracts/facets/DiamondLoupeFacet.sol` file shows how to implement the four standard loupe functions.

The `contracts/libraries/LibLaunchPadProjectStorage.sol` file shows how to implement Diamond Storage.

## Calling Diamond Functions

In order to call a function that exists in a diamond you need to use the ABI information of the facet that has the function.

## Useful Links

1. [EIP-2535 Diamonds](https://eips.ethereum.org/EIPS/eip-2535)
1. [diamond-3-hardhat](https://github.com/mudgen/diamond-3-hardhat)
1. [Introduction to EIP-2535 Diamonds](https://eip2535diamonds.substack.com/p/introduction-to-the-diamond-standard)
1. [Solidity Storage Layout For Proxy Contracts and Diamonds](https://medium.com/1milliondevs/solidity-storage-layout-for-proxy-contracts-and-diamonds-c4f009b6903)
1. [New Storage Layout For Proxy Contracts and Diamonds](https://medium.com/1milliondevs/new-storage-layout-for-proxy-contracts-and-diamonds-98d01d0eadb)
1. [Diamond Setter](https://github.com/lampshade9909/DiamondSetter)
1. [Upgradeable smart contracts using the EIP-2535 Diamonds](https://hiddentao.com/archives/2020/05/28/upgradeable-smart-contracts-using-diamond-standard)
1. [buidler-deploy supports diamonds](https://github.com/wighawag/buidler-deploy/)

## Author

This implementation was written by Jenson.

Contact:

- https://twitter.com/NonFungibleJC
- nonfungiblejc@gmail.com

## License

MIT license. See the license file.
Anyone can use or modify this software for their purposes.
