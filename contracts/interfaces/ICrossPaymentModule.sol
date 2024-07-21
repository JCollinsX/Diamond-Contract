// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IPaymentModule } from "./IPaymentModule.sol";

interface ICrossPaymentModule {
    struct CrossPaymentSignatureInput {
        address payer;
        uint256 sourceChainId;
        uint256 paymentIndex;
        bytes signature;
    }

    struct ProcessCrossPaymentOutput {
        bytes32 platformId;
        uint32[] services;
        uint32[] serviceAmounts;
        address spender;
        uint256 destinationChainId;
        address payer;
        uint256 sourceChainId;
        uint256 paymentIndex;
    }

    function updateCrossPaymentSignerAddress(address newSignerAddress) external;
    function processCrossPayment(
        IPaymentModule.ProcessPaymentInput memory paymentInput,
        address spender,
        uint256 destinationChainId
    ) external payable returns (uint256);
    function processCrossPaymentForDelegator(
        IPaymentModule.ProcessPaymentInput memory paymentInput,
        address delegator,
        uint256 destinationChainId,
        uint256 gasFee,
        bytes memory signature
    ) external payable returns (uint256);
    function processCrossPaymentBuyTokenForDelegator(
        IPaymentModule.ProcessPaymentInput memory paymentInput,
        address delegator,
        uint256 gasFee,
        bytes memory signature
    ) external payable returns (uint256);
    function spendCrossPaymentSignature(address spender, ProcessCrossPaymentOutput memory output, bytes memory signature) external;
    function getCrossPaymentSignerAddress() external view returns (address);
    function getCrossPaymentOutputByIndex(uint256 paymentIndex) external view returns (ProcessCrossPaymentOutput memory);
    function prefixedMessage(bytes32 hash) external pure returns (bytes32);
    function getHashedMessage(ProcessCrossPaymentOutput memory output) external pure returns (bytes32);
    function recoverSigner(bytes32 message, bytes memory signature) external pure returns (address);
    function checkSignature(ProcessCrossPaymentOutput memory output, bytes memory signature) external view;
    function getDelegatorHashedMessage(address delegator, uint256 destinationChainId, uint256 gasFee) external pure returns (bytes32);
    function checkDelegatorSignature(address delegator, uint256 destinationChainId, uint256 gasFee, bytes memory signature) external pure;
    function getDelegatorBuyTokenHashedMessage(
        address delegator,
        address destinationAddress,
        uint32 destinationChainId,
        uint256 gasFee
    ) external pure returns (bytes32);
    function checkDelegatorBuyTokenSignature(
        address delegator,
        address destinationAddress,
        uint32 destinationChainId,
        uint256 gasFee,
        bytes memory signature
    ) external pure;
    function getChainID() external view returns (uint256);

    /** EVENTS */
    event CrossPaymentProcessed(uint256 indexed previousBlock, uint256 indexed paymentIndex);
    event CrossPaymentSignatureSpent(uint256 indexed previousBlock, uint256 indexed sourceChainId, uint256 indexed paymentIndex);
    event CrossPaymentSignerAddressUpdated(address indexed oldSigner, address indexed newSigner);
    event CrossPaymentProcessedBuyToken(
        uint256 indexed paymentIndex,
        address delegator,
        uint256 indexed destinationChainId,
        address indexed destinationAddress
    );

    /** ERRORS */
    error ProcessCrossPaymentError(string errorMessage);
    error CheckSignatureError(string errorMessage);
    error ProcessCrossPaymentSignatureError(string errorMessage);
}
