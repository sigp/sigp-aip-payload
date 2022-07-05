// SPDX-License-Identifier: MIT
// Modified from BgD Aave Payload @ https://github.com/bgd-labs/aave-ecosystem-reserve-v2/blob/master/src/PayloadAaveBGD.sol

pragma solidity 0.8.11;

import {AaveEcosystemReserveController} from "./AaveEcosystemReserveController.sol";
import {AaveEcosystemReserveV2} from "./AaveEcosystemReserveV2.sol";
import {IInitializableAdminUpgradeabilityProxy} from "src/interfaces/IInitializableAdminUpgradeabilityProxy.sol";
import {IAaveEcosystemReserveController} from "src/interfaces/IAaveEcosystemReserveController.sol";
import {IStreamable} from "src/interfaces/IStreamable.sol";
import {IAdminControlledEcosystemReserve} from "src/interfaces/IAdminControlledEcosystemReserve.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract PayloadAaveSigP {
    IInitializableAdminUpgradeabilityProxy public constant COLLECTOR_V2_PROXY =
        IInitializableAdminUpgradeabilityProxy(
            0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c
        );

    IAaveEcosystemReserveController public constant CONTROLLER_OF_COLLECTOR =
        IAaveEcosystemReserveController(
            0x3d569673dAa0575c936c7c67c4E6AedA69CC630C
        );

    address public constant GOV_SHORT_EXECUTOR =
        0xEE56e2B3D491590B5b31738cC34d5232F378a8D5;

    IERC20 public constant AUSDC =
        IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    IERC20 public constant AUSDT =
        IERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);

    // As per the offchain governance proposal
    // 50% upfront payment, 50% streamed with:
    // Start stream time = block.timestamp + 6 months
    // End streat time = block.timestamp + 12 months
    // (splits payment equally between aUSDC and aUSDT):


    uint256 public constant FEE = 1296000 * 1e6; // $1,296,000. Minimum engagement fee as per proposal
    uint256 public constant UPFRONT_AMOUNT = 648000 * 1e6;// FEE / 2; // 50% of the fee

    uint256 public constant AUSDC_UPFRONT_AMOUNT = 324000 * 1e6; // UPFRONT_AMOUNT / 2; // 324,000 aUSDC
    uint256 public constant AUSDT_UPFRONT_AMOUNT = 324000 * 1e6; // UPFRONT_AMOUNT / 2; // 324,000 aUSDT

    uint256 public constant AUSDC_STREAM_AMOUNT = 324010368000; // ~324,000 aUSDC. A bit more for the streaming requirements
    uint256 public constant AUSDT_STREAM_AMOUNT = 324010368000; // ~324,000 aUSDT. A bit more for the streaming requirements

    uint256 public constant STREAMS_DURATION = 180 days; // 6 months of 30 days
    uint256 public constant STREAMS_DELAY = 180 days; // 6 months of 30 days

    address public constant SIGP =
        address(0xC9a872868afA68BA937f65A1c5b4B252dAB15D85);

    function execute() external {

        // Transfer of the upfront payment, 50% of the total engagement fee, split in aUSDC and aUSDT.
        CONTROLLER_OF_COLLECTOR.transfer(
            address(COLLECTOR_V2_PROXY),
            AUSDC,
            SIGP,
            AUSDC_UPFRONT_AMOUNT
        );

        CONTROLLER_OF_COLLECTOR.transfer(
            address(COLLECTOR_V2_PROXY),
            AUSDT,
            SIGP,
            AUSDT_UPFRONT_AMOUNT
        );

        // Creation of the streams

        // aUSDC stream
        // 6 months stream, starting 6 months from now
        CONTROLLER_OF_COLLECTOR.createStream(
            address(COLLECTOR_V2_PROXY),
            SIGP,
            AUSDC_STREAM_AMOUNT,
            AUSDC,
            block.timestamp + STREAMS_DELAY,
            block.timestamp + STREAMS_DELAY + STREAMS_DURATION
        );

        // aUSDT stream
        // 6 months stream, starting 6 months from now
        CONTROLLER_OF_COLLECTOR.createStream(
            address(COLLECTOR_V2_PROXY),
            SIGP,
            AUSDT_STREAM_AMOUNT,
            AUSDT,
            block.timestamp + STREAMS_DELAY,
            block.timestamp + STREAMS_DELAY + STREAMS_DURATION
        );
    }
}
