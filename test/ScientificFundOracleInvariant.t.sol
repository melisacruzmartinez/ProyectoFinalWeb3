// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ScientificFundOracle} from "../contracts/ScientificFundOracle.sol";
import {ScientificOracle} from "../contracts/ScientificOracle.sol";

/// @dev Ejecuta acciones validas al azar sobre el fondo para que el fuzzer explore secuencias reales.
contract FundHandler is Test {
    ScientificFundOracle internal fund;
    address internal projectOwner;
    address[3] internal auditors;

    uint256 public ghostDonated;
    uint256 public ghostReleased;

    constructor(ScientificFundOracle fund_, address projectOwner_, address[3] memory auditors_) {
        fund = fund_;
        projectOwner = projectOwner_;
        auditors = auditors_;
    }

    function contribute(uint256 donorSeed, uint96 amount) external {
        address donor = address(uint160(bound(donorSeed, 1_000, 1_100)));
        uint256 value = bound(amount, 1, 10 ether);
        deal(donor, value);

        vm.prank(donor);
        fund.contribute{value: value}();
        ghostDonated += value;
    }

    function createMilestone(uint96 amount) external {
        vm.prank(projectOwner);
        fund.createMilestone("Fase", "QmEvidencia", bound(amount, 1, 20 ether));
    }

    function vote(uint256 milestoneSeed, uint256 auditorSeed, bool support) external {
        uint256 count = fund.milestoneCount();
        if (count == 0) return;
        uint256 id = bound(milestoneSeed, 0, count - 1);
        address auditor = auditors[bound(auditorSeed, 0, 2)];
        if (fund.hasVoted(id, auditor) || fund.isMilestoneReleased(id)) return;

        vm.prank(auditor);
        fund.voteMilestone(id, support);
    }

    function validateAndRelease(uint256 milestoneSeed) external {
        uint256 count = fund.milestoneCount();
        if (count == 0) return;
        uint256 id = bound(milestoneSeed, 0, count - 1);
        if (fund.isMilestoneReleased(id)) return;

        fund.validateMilestone(id);
        (uint128 amount, uint32 votesFor,,,,,) = fund.milestones(id);
        if (votesFor < fund.approvalsRequired() || address(fund).balance < amount) return;

        vm.prank(projectOwner);
        fund.releaseMilestone(id);
        ghostReleased += amount;
    }
}

contract ScientificFundOracleInvariantTest is Test {
    ScientificFundOracle internal fund;
    FundHandler internal handler;

    function setUp() public {
        address projectOwner = makeAddr("projectOwner");
        address[3] memory list = [makeAddr("auditor1"), makeAddr("auditor2"), makeAddr("auditor3")];
        address[] memory auditors = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            auditors[i] = list[i];
        }

        fund = new ScientificFundOracle(projectOwner, auditors, address(new ScientificOracle()));
        handler = new FundHandler(fund, projectOwner, list);
        targetContract(address(handler));
    }

    function invariant_BalanceMatchesAccounting() public view {
        assertEq(address(fund).balance, fund.totalRaised() - fund.totalReleased());
    }

    function invariant_NeverReleasesMoreThanRaised() public view {
        assertLe(fund.totalReleased(), fund.totalRaised());
    }

    function invariant_TotalsMatchGhostVariables() public view {
        assertEq(fund.totalRaised(), handler.ghostDonated());
        assertEq(fund.totalReleased(), handler.ghostReleased());
    }
}
