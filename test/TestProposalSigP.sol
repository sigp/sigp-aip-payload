// SPDX-License-Identifier: MIT
// Adapted from BdD Aave Tests @ https://github.com/bgd-labs/aave-ecosystem-reserve-v2/blob/master/src/test/ValidationProposal.sol

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

contract TestProposal is BaseTest {
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

    function init(address payload) internal returns(uint256 proposalId) {

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

      proposalId = AaveGovHelpers._createProposal(
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

    }



    function testPayloadSigP() public {

      address payload = address(new PayloadAaveSigP());

      _testProposalSigP(payload);

    }

    function _testProposalSigP(address payload) internal {

        uint256 proposalId = init(payload);

        _validatePostProposalUpfronts(proposalId);
        _validatePostProposalStreamsSigP(proposalId);
    }

    function _validatePostProposalUpfronts(uint256 proposalId) internal {

      IAaveGov.ProposalWithoutVotes memory proposalData = AaveGovHelpers
          ._getProposalById(proposalId);
      address payload = proposalData.targets[0];

      uint256 upfront = PayloadAaveSigP(payload).UPFRONT_AMOUNT();
      address sigp = PayloadAaveSigP(payload).SIGP();
      IERC20 aUsdc = PayloadAaveSigP(payload).AUSDC();
      IERC20 aUsdt = PayloadAaveSigP(payload).AUSDT();
      console.log("Here");
      assertLe(upfront / 2, aUsdc.balanceOf(sigp));
      assertLe(upfront / 2, aUsdt.balanceOf(sigp));
      console.log("There");
}

    function _validatePostProposalStreamsSigP(uint256 proposalId) internal {
        IAaveGov.ProposalWithoutVotes memory proposalData = AaveGovHelpers
            ._getProposalById(proposalId);
        address payload = proposalData.targets[0];

        IStreamable collectorProxy = IStreamable(
            address(PayloadAaveSigP(payload).COLLECTOR_V2_PROXY())
        );

        (, , , , uint256 startTime, , , ) = collectorProxy
            .getStream(100001);

        address sigp = PayloadAaveSigP(payload).SIGP();
        IERC20 aUsdc = PayloadAaveSigP(payload).AUSDC();
        IERC20 aUsdt = PayloadAaveSigP(payload).AUSDT();

        uint256 recipientAUsdcBalanceBefore = aUsdc.balanceOf(sigp);
        uint256 recipientAUsdtBalanceBefore = aUsdt.balanceOf(sigp);

        vm.warp(block.timestamp + 30 days);
        vm.startPrank(sigp);

        assertEq(collectorProxy.balanceOf(100001, sigp), 0);
        assertEq(collectorProxy.balanceOf(100002, sigp), 0);

        vm.warp(block.timestamp + 151 days);

        assertGt(collectorProxy.balanceOf(100001, sigp), 0);
        assertGt(collectorProxy.balanceOf(100002, sigp), 0);

        assert(block.timestamp > startTime);

        collectorProxy.withdrawFromStream(
            100001,
            collectorProxy.balanceOf(100001, sigp)
        );

        collectorProxy.withdrawFromStream(
            100002,
            collectorProxy.balanceOf(100002, sigp)
        );

        assert(recipientAUsdcBalanceBefore < aUsdc.balanceOf(sigp));
        assert(recipientAUsdtBalanceBefore < aUsdt.balanceOf(sigp));

        vm.warp(block.timestamp + 200 days);
        uint256 totalFee = uint256(PayloadAaveSigP(payload).FEE());

        collectorProxy.withdrawFromStream(
            100001,
            collectorProxy.balanceOf(100001, sigp)
        );

        collectorProxy.withdrawFromStream(
            100002,
            collectorProxy.balanceOf(100002, sigp)
        );

        assert(totalFee < aUsdc.balanceOf(sigp) + aUsdt.balanceOf(sigp));

        vm.expectRevert(bytes("stream does not exist"));
        collectorProxy.balanceOf(100001, sigp);

        vm.stopPrank();
    }

}
