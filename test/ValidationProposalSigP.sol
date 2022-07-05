// SPDX-License-Identifier: MIT
// Modified from BdD Aave Tests @ https://github.com/bgd-labs/aave-ecosystem-reserve-v2/blob/master/src/test/ValidationProposal.sol

pragma solidity 0.8.11;

import {BaseTest} from "./base/BaseTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IStreamable} from "src/interfaces/IStreamable.sol";
import {IOwnable} from "src/interfaces/IOwnable.sol";
import {IAdminControlledEcosystemReserve} from "src/interfaces/IAdminControlledEcosystemReserve.sol";
import {IAaveEcosystemReserveController} from "src/interfaces/IAaveEcosystemReserveController.sol";
import {IInitializableAdminUpgradeabilityProxy} from "src/interfaces/IInitializableAdminUpgradeabilityProxy.sol";
import {PayloadAaveSigP} from "src/PayloadAaveSigP.sol";
import {AaveGovHelpers, IAaveGov} from "./utils/AaveGovHelpers.sol";
import {ApproximateMath} from "./utils/ApproximateMath.sol";
import {console} from "./utils/console.sol";

contract ValidationProposal is BaseTest {
    address internal constant AAVE_WHALE =
        0x25F2226B597E8F9514B3F68F00f494cF4f286491;

    error InvalidTransferOfUpfront(
        IERC20 asset,
        uint256 expectedBalance,
        uint256 currentBalance
    );

    error InvalidBalanceAfterWithdraw(
        IERC20 asset,
        uint256 expectedBalance,
        uint256 currentBalance
    );

    error WrongOwnerOfController(address expect, address current);

    error InconsistentFundsAdminOfReserves(
        address controllerOfProtocolReserve,
        address controllerOfAaveReserve
    );

    function setUp() public {}

    function testProposalPrePayload() public {
        address payload = address(new PayloadAaveSigP());

        _testProposal(payload);
    }

    function _testProposal(address payload) internal {
        address[] memory targets = new address[](1);
        targets[0] = payload;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        string[] memory signatures = new string[](1);
        signatures[0] = "execute()";
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        bool[] memory withDelegatecalls = new bool[](1);
        withDelegatecalls[0] = true;

        uint256 proposalId = AaveGovHelpers._createProposal(
            vm,
            AAVE_WHALE,
            IAaveGov.SPropCreateParams({
                executor: AaveGovHelpers.SHORT_EXECUTOR,
                targets: targets,
                values: values,
                signatures: signatures,
                calldatas: calldatas,
                withDelegatecalls: withDelegatecalls,
                ipfsHash: bytes32(0)
            })
        );

        AaveGovHelpers._passVote(vm, AAVE_WHALE, proposalId);

        _validatePostProposalUpfronts(proposalId);
        _validatePostProposalStreams(proposalId);
        _validatePostProposalACL(proposalId);
    }

    function _validatePostProposalUpfronts(uint256 proposalId) internal view {
        IAaveGov.ProposalWithoutVotes memory proposalData = AaveGovHelpers
            ._getProposalById(proposalId);
        // Generally, there is no reason to have more than 1 payload if using the DELEGATECALL pattern
        address payload = proposalData.targets[0];

        if (
            !ApproximateMath._almostEqual(
                IERC20(PayloadAaveSigP(payload).AUSDC()).balanceOf(
                    PayloadAaveSigP(payload).SIGP()
                ),
                PayloadAaveSigP(payload).AUSDC_UPFRONT_AMOUNT()
            )
        ) {
            revert InvalidTransferOfUpfront(
                PayloadAaveSigP(payload).AUSDC(),
                PayloadAaveSigP(payload).AUSDC_UPFRONT_AMOUNT(),
                IERC20(PayloadAaveSigP(payload).AUSDC()).balanceOf(
                    PayloadAaveSigP(payload).SIGP()
                )
            );
        }

        if (
            !ApproximateMath._almostEqual(
                IERC20(PayloadAaveSigP(payload).AUSDT()).balanceOf(
                    PayloadAaveSigP(payload).SIGP()
                ),
                PayloadAaveSigP(payload).AUSDT_UPFRONT_AMOUNT()
            )
        ) {
            revert InvalidTransferOfUpfront(
                PayloadAaveSigP(payload).AUSDT(),
                PayloadAaveSigP(payload).AUSDT_UPFRONT_AMOUNT(),
                IERC20(PayloadAaveSigP(payload).AUSDT()).balanceOf(
                    PayloadAaveSigP(payload).SIGP()
                )
            );
        }

    }

    function _validatePostProposalStreams(uint256 proposalId) internal {
        IAaveGov.ProposalWithoutVotes memory proposalData = AaveGovHelpers
            ._getProposalById(proposalId);
        address payload = proposalData.targets[0];

        IStreamable collectorProxy = IStreamable(
            address(PayloadAaveSigP(payload).COLLECTOR_V2_PROXY())
        );
        // IStreamable aaveCollectorProxy = IStreamable(
        //     address(PayloadAaveSigP(payload).AAVE_TOKEN_COLLECTOR_PROXY())
        // );
        (, , , , uint256 startTime, , , uint256 ratePerSecond) = collectorProxy
            .getStream(100001);

        // (, , , , , , , uint256 ratePerSecondAave) = aaveCollectorProxy
        //     .getStream(100000);

        vm.warp(startTime + 1 days);
        address sigp = PayloadAaveSigP(payload).SIGP();
        IERC20 aUsdc = PayloadAaveSigP(payload).AUSDC();
        IERC20 aUsdt = PayloadAaveSigP(payload).AUSDT();

        uint256 recipientAUsdcBalanceBefore = aUsdc.balanceOf(sigp);
        uint256 recipientAUsdtBalanceBefore = aUsdt.balanceOf(sigp);

        vm.startPrank(sigp);

        collectorProxy.withdrawFromStream(
            100001,
            collectorProxy.balanceOf(100001, sigp)
        );

        collectorProxy.withdrawFromStream(
            100002,
            collectorProxy.balanceOf(100002, sigp)
        );

        if (
            aUsdc.balanceOf(sigp) <
            (recipientAUsdcBalanceBefore + (ratePerSecond * 1 days))
        ) {
            revert InvalidBalanceAfterWithdraw(
                aUsdc,
                recipientAUsdcBalanceBefore + (ratePerSecond * 1 days),
                aUsdc.balanceOf(sigp)
            );
        }

        if (
            aUsdt.balanceOf(sigp) <
            (recipientAUsdtBalanceBefore + (ratePerSecond * 1 days))
        ) {
            revert InvalidBalanceAfterWithdraw(
                aUsdt,
                recipientAUsdtBalanceBefore + (ratePerSecond * 1 days),
                aUsdt.balanceOf(sigp)
            );
        }

        vm.stopPrank();
    }

    function _validatePostProposalACL(uint256 proposalId) internal {
        IAaveGov.ProposalWithoutVotes memory proposalData = AaveGovHelpers
            ._getProposalById(proposalId);
        PayloadAaveSigP payload = PayloadAaveSigP(proposalData.targets[0]);

        address protocolReserve = address(
            PayloadAaveSigP(payload).COLLECTOR_V2_PROXY()
        );
        // address aaveReserve = address(
        //     PayloadAaveSigP(payload).AAVE_TOKEN_COLLECTOR_PROXY()
        // );

        // The controller of the reserve for both protocol's and AAVE treasuries is owned by the short executor
        address controllerOfProtocolReserve = IAdminControlledEcosystemReserve(
            protocolReserve
        ).getFundsAdmin();

        // address controllerOfAaveReserve = IAdminControlledEcosystemReserve(
        //     aaveReserve
        // ).getFundsAdmin();

        address shortExecutor = payload.GOV_SHORT_EXECUTOR();

        // if (controllerOfProtocolReserve != controllerOfAaveReserve) {
        //     revert InconsistentFundsAdminOfReserves(
        //         controllerOfProtocolReserve,
        //         controllerOfAaveReserve
        //     );
        // }

        if (IOwnable(controllerOfProtocolReserve).owner() != shortExecutor) {
            revert WrongOwnerOfController(
                shortExecutor,
                IOwnable(controllerOfProtocolReserve).owner()
            );
        }

        vm.startPrank(address(1));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IAaveEcosystemReserveController(controllerOfProtocolReserve).approve(
            address(0),
            IERC20(address(0)),
            address(0),
            0
        );
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IAaveEcosystemReserveController(controllerOfProtocolReserve).transfer(
            address(0),
            IERC20(address(0)),
            address(0),
            0
        );

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IAaveEcosystemReserveController(controllerOfProtocolReserve)
            .createStream(address(0), address(0), 0, IERC20(address(0)), 0, 0);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IAaveEcosystemReserveController(controllerOfProtocolReserve)
            .cancelStream(address(0), 0);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IAaveEcosystemReserveController(controllerOfProtocolReserve)
            .withdrawFromStream(address(0), 0, 0);

        vm.stopPrank();

        // Test of ownership of treasuries' by short executor. Only proxy's owner can call admin()
        vm.startPrank(shortExecutor);
        IInitializableAdminUpgradeabilityProxy(protocolReserve).admin();
        vm.stopPrank();

        // ACL of the protocols's ecosystem reserve functions. Only by controller of reserve
        vm.startPrank(address(1));
        vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        IAdminControlledEcosystemReserve(protocolReserve).approve(
            IERC20(address(0)),
            address(0),
            0
        );
        vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        IAdminControlledEcosystemReserve(protocolReserve).transfer(
            IERC20(address(0)),
            address(0),
            0
        );

        vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        IStreamable(protocolReserve).createStream(
            address(0),
            0,
            address(0),
            0,
            0
        );

        vm.expectRevert(
            bytes(
                "caller is not the funds admin or the recipient of the stream"
            )
        );
        IStreamable(protocolReserve).cancelStream(100001);

        vm.expectRevert(
            bytes(
                "caller is not the funds admin or the recipient of the stream"
            )
        );
        IStreamable(protocolReserve).withdrawFromStream(100001, 0);

        // // ACL of the AAVE's ecosystem reserve functions. Only by controller of reserve
        //
        // vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        // IAdminControlledEcosystemReserve(aaveReserve).approve(
        //     IERC20(address(0)),
        //     address(0),
        //     0
        // );
        // vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        // IAdminControlledEcosystemReserve(aaveReserve).transfer(
        //     IERC20(address(0)),
        //     address(0),
        //     0
        // );
        //
        // vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        // IStreamable(aaveReserve).createStream(address(0), 0, address(0), 0, 0);
        //
        // vm.expectRevert(
        //     bytes(
        //         "caller is not the funds admin or the recipient of the stream"
        //     )
        // );
        // IStreamable(aaveReserve).cancelStream(100000);
        //
        // vm.expectRevert(
        //     bytes(
        //         "caller is not the funds admin or the recipient of the stream"
        //     )
        // );
        // IStreamable(aaveReserve).withdrawFromStream(100000, 0);

        vm.stopPrank();
    }
}
