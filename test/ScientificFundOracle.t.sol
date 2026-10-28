// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ScientificFundOracle} from "../contracts/ScientificFundOracle.sol";
import {ScientificOracle} from "../contracts/ScientificOracle.sol";
import {IScientificOracle} from "../contracts/interfaces/IScientificOracle.sol";

/// @dev Oráculo configurable para simular rechazos.
contract MockOracle is IScientificOracle {
    bool public approved = true;

    function setApproved(bool _approved) external {
        approved = _approved;
    }

    function validateMilestone(address, uint256, string calldata, uint256) external view returns (bool) {
        return approved;
    }
}

/// @dev Receptor que rechaza ETH, para probar TransferFailed.
contract RejectingOwner {
    receive() external payable {
        revert("no ETH");
    }
}

/// @dev Receptor que intenta reentrar en releaseMilestone.
contract ReentrantOwner {
    ScientificFundOracle public fund;
    bool internal attacked;

    function setFund(ScientificFundOracle _fund) external {
        fund = _fund;
    }

    function create(string calldata t, string calldata h, uint256 a) external {
        fund.createMilestone(t, h, a);
    }

    function release(uint256 id) external {
        fund.releaseMilestone(id);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            fund.releaseMilestone(1);
        }
    }
}

contract ScientificFundOracleTest is Test {
    ScientificFundOracle internal fund;
    ScientificOracle internal oracle;
    MockOracle internal mock;

    address internal projectOwner = makeAddr("projectOwner");
    address internal auditor1 = makeAddr("auditor1");
    address internal auditor2 = makeAddr("auditor2");
    address internal auditor3 = makeAddr("auditor3");
    address internal donor = makeAddr("donor");
    address internal stranger = makeAddr("stranger");

    event Contribution(address indexed donor, uint256 amount, uint256 totalRaised);
    event MilestoneReleased(uint256 indexed milestoneId, uint256 amount, address indexed recipient);

    function _auditors() internal view returns (address[] memory list) {
        list = new address[](3);
        list[0] = auditor1;
        list[1] = auditor2;
        list[2] = auditor3;
    }

    function setUp() public {
        oracle = new ScientificOracle();
        mock = new MockOracle();
        fund = new ScientificFundOracle(projectOwner, _auditors(), address(oracle));
        deal(donor, 100 ether);
    }

    // ---------- helpers ----------

    function _donate(uint256 amount) internal {
        vm.prank(donor);
        fund.contribute{value: amount}();
    }

    function _create(uint256 amount) internal returns (uint256 id) {
        vm.prank(projectOwner);
        id = fund.createMilestone("Fase 1: prototipo", "QmEvidencia001", amount);
    }

    function _vote(uint256 id, bool a1, bool a2, bool a3) internal {
        vm.prank(auditor1);
        fund.voteMilestone(id, a1);
        vm.prank(auditor2);
        fund.voteMilestone(id, a2);
        vm.prank(auditor3);
        fund.voteMilestone(id, a3);
    }

    // ---------- happy path ----------

    function test_FullFlow_DonateVoteValidateRelease() public {
        _donate(5 ether);
        uint256 id = _create(2 ether);
        _vote(id, true, true, false);
        assertTrue(fund.validateMilestone(id));

        vm.expectEmit(true, true, false, true);
        emit MilestoneReleased(id, 2 ether, projectOwner);
        vm.prank(projectOwner);
        fund.releaseMilestone(id);

        assertEq(projectOwner.balance, 2 ether);
        assertEq(fund.totalReleased(), 2 ether);
        assertEq(address(fund).balance, 3 ether);
        assertTrue(fund.isMilestoneReleased(id));
    }

    function test_TwoMilestones_UseRemainingBalance() public {
        _donate(5 ether);
        uint256 first = _create(2 ether);
        _vote(first, true, true, true);
        fund.validateMilestone(first);
        vm.prank(projectOwner);
        fund.releaseMilestone(first);

        // Regresión: antes el chequeo de saldo contaba dos veces lo ya liberado.
        uint256 second = _create(3 ether);
        _vote(second, true, true, false);
        fund.validateMilestone(second);
        vm.prank(projectOwner);
        fund.releaseMilestone(second);

        assertEq(fund.totalReleased(), 5 ether);
        assertEq(address(fund).balance, 0);
    }

    function test_Contribute_TracksDonorAndEmits() public {
        vm.expectEmit(true, false, false, true);
        emit Contribution(donor, 1 ether, 1 ether);
        _donate(1 ether);
        _donate(2 ether);
        assertEq(fund.contributions(donor), 3 ether);
        assertEq(fund.totalRaised(), 3 ether);
    }

    function test_Views() public view {
        assertEq(fund.auditorCount(), 3);
        assertEq(fund.approvalsRequired(), 2);
        assertEq(address(fund.oracle()), address(oracle));
        assertEq(fund.owner(), projectOwner);
        assertTrue(fund.isAuditor(auditor2));
        assertFalse(fund.isAuditor(stranger));
    }

    function test_VoteCountsAndHasVoted() public {
        uint256 id = _create(1 ether);
        _vote(id, true, false, false);
        (uint128 amount, uint32 votesFor, uint32 votesAgainst,,,,) = fund.milestones(id);
        assertEq(amount, 1 ether);
        assertEq(votesFor, 1);
        assertEq(votesAgainst, 2);
        assertTrue(fund.hasVoted(id, auditor1));
    }

    // ---------- constructor ----------

    function test_RevertWhen_ConstructorNoAuditors() public {
        vm.expectRevert(ScientificFundOracle.NoAuditors.selector);
        new ScientificFundOracle(projectOwner, new address[](0), address(oracle));
    }

    function test_RevertWhen_ConstructorZeroOracle() public {
        vm.expectRevert(ScientificFundOracle.ZeroAddress.selector);
        new ScientificFundOracle(projectOwner, _auditors(), address(0));
    }

    function test_RevertWhen_ConstructorZeroAuditor() public {
        address[] memory list = new address[](1);
        vm.expectRevert(ScientificFundOracle.ZeroAddress.selector);
        new ScientificFundOracle(projectOwner, list, address(oracle));
    }

    function test_RevertWhen_ConstructorZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ScientificFundOracle(address(0), _auditors(), address(oracle));
    }

    function test_Constructor_IgnoresDuplicateAuditors() public {
        address[] memory list = new address[](3);
        list[0] = auditor1;
        list[1] = auditor1;
        list[2] = auditor2;
        ScientificFundOracle f = new ScientificFundOracle(projectOwner, list, address(oracle));
        assertEq(f.auditorCount(), 2);
    }

    // ---------- contribute / create ----------

    function test_RevertWhen_ContributeZero() public {
        vm.expectRevert(ScientificFundOracle.InvalidAmount.selector);
        fund.contribute{value: 0}();
    }

    function test_RevertWhen_CreateNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        fund.createMilestone("t", "h", 1);
    }

    function test_RevertWhen_CreateEmptyTitle() public {
        vm.prank(projectOwner);
        vm.expectRevert(ScientificFundOracle.EmptyTitle.selector);
        fund.createMilestone("", "h", 1);
    }

    function test_RevertWhen_CreateEmptyHash() public {
        vm.prank(projectOwner);
        vm.expectRevert(ScientificFundOracle.EmptyIpfsHash.selector);
        fund.createMilestone("t", "", 1);
    }

    function test_RevertWhen_CreateZeroAmount() public {
        vm.prank(projectOwner);
        vm.expectRevert(ScientificFundOracle.InvalidAmount.selector);
        fund.createMilestone("t", "h", 0);
    }

    function test_RevertWhen_CreateAmountOverflow() public {
        vm.prank(projectOwner);
        vm.expectRevert(ScientificFundOracle.InvalidAmount.selector);
        fund.createMilestone("t", "h", uint256(type(uint128).max) + 1);
    }

    // ---------- vote ----------

    function test_RevertWhen_VoteNotAuditor() public {
        uint256 id = _create(1 ether);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.NotAuditor.selector, stranger));
        fund.voteMilestone(id, true);
    }

    function test_RevertWhen_VoteTwice() public {
        uint256 id = _create(1 ether);
        vm.startPrank(auditor1);
        fund.voteMilestone(id, true);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.AlreadyVoted.selector, id, auditor1));
        fund.voteMilestone(id, false);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteMissingMilestone() public {
        vm.prank(auditor1);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneNotFound.selector, 7));
        fund.voteMilestone(7, true);
    }

    function test_RevertWhen_VoteAfterRelease() public {
        _donate(1 ether);
        uint256 id = _create(1 ether);
        vm.prank(auditor1);
        fund.voteMilestone(id, true);
        vm.prank(auditor2);
        fund.voteMilestone(id, true);
        fund.validateMilestone(id);
        vm.prank(projectOwner);
        fund.releaseMilestone(id);

        vm.prank(auditor3);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneAlreadyReleased.selector, id));
        fund.voteMilestone(id, true);
    }

    // ---------- validate ----------

    function test_RevertWhen_ValidateMissingMilestone() public {
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneNotFound.selector, 0));
        fund.validateMilestone(0);
    }

    function test_RevertWhen_ValidateAfterRelease() public {
        _donate(1 ether);
        uint256 id = _create(1 ether);
        _vote(id, true, true, true);
        fund.validateMilestone(id);
        vm.prank(projectOwner);
        fund.releaseMilestone(id);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneAlreadyReleased.selector, id));
        fund.validateMilestone(id);
    }

    // ---------- release ----------

    function test_RevertWhen_ReleaseWithoutOracleValidation() public {
        _donate(5 ether);
        uint256 id = _create(1 ether);
        _vote(id, true, true, true);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.OracleRejected.selector, id));
        fund.releaseMilestone(id);
    }

    function test_RevertWhen_OracleRejects() public {
        ScientificFundOracle f = new ScientificFundOracle(projectOwner, _auditors(), address(mock));
        mock.setApproved(false);
        vm.prank(donor);
        f.contribute{value: 1 ether}();
        vm.prank(projectOwner);
        uint256 id = f.createMilestone("t", "h", 1 ether);
        vm.prank(auditor1);
        f.voteMilestone(id, true);
        vm.prank(auditor2);
        f.voteMilestone(id, true);
        assertFalse(f.validateMilestone(id));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.OracleRejected.selector, id));
        f.releaseMilestone(id);
    }

    function test_RevertWhen_ReleaseWithoutMajority() public {
        _donate(5 ether);
        uint256 id = _create(1 ether);
        _vote(id, true, false, false);
        fund.validateMilestone(id);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.NoApproval.selector, 1, 2));
        fund.releaseMilestone(id);
    }

    function test_RevertWhen_ReleaseInsufficientBalance() public {
        _donate(1 ether);
        uint256 id = _create(2 ether);
        _vote(id, true, true, true);
        fund.validateMilestone(id);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.InsufficientBalance.selector, 1 ether, 2 ether));
        fund.releaseMilestone(id);
    }

    function test_RevertWhen_ReleaseTwice() public {
        _donate(5 ether);
        uint256 id = _create(1 ether);
        _vote(id, true, true, true);
        fund.validateMilestone(id);
        vm.startPrank(projectOwner);
        fund.releaseMilestone(id);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneAlreadyReleased.selector, id));
        fund.releaseMilestone(id);
        vm.stopPrank();
    }

    function test_RevertWhen_ReleaseNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        fund.releaseMilestone(0);
    }

    function test_RevertWhen_ReleaseMissingMilestone() public {
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneNotFound.selector, 3));
        fund.releaseMilestone(3);
    }

    function test_RevertWhen_IsReleasedMissingMilestone() public {
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.MilestoneNotFound.selector, 0));
        fund.isMilestoneReleased(0);
    }

    function test_RevertWhen_TransferFails() public {
        RejectingOwner bad = new RejectingOwner();
        ScientificFundOracle f = new ScientificFundOracle(address(bad), _auditors(), address(oracle));
        vm.prank(donor);
        f.contribute{value: 1 ether}();
        vm.prank(address(bad));
        uint256 id = f.createMilestone("t", "h", 1 ether);
        vm.prank(auditor1);
        f.voteMilestone(id, true);
        vm.prank(auditor2);
        f.voteMilestone(id, true);
        f.validateMilestone(id);

        vm.prank(address(bad));
        vm.expectRevert(ScientificFundOracle.TransferFailed.selector);
        f.releaseMilestone(id);
    }

    function test_RevertWhen_Reentrancy() public {
        ReentrantOwner attacker = new ReentrantOwner();
        ScientificFundOracle f = new ScientificFundOracle(address(attacker), _auditors(), address(oracle));
        attacker.setFund(f);
        vm.prank(donor);
        f.contribute{value: 5 ether}();
        attacker.create("a", "h", 1 ether);
        attacker.create("b", "h", 1 ether);
        for (uint256 id; id < 2; ++id) {
            vm.prank(auditor1);
            f.voteMilestone(id, true);
            vm.prank(auditor2);
            f.voteMilestone(id, true);
            f.validateMilestone(id);
        }
        // La reentrada revierte (ReentrancyGuard) y eso hace fallar la transferencia.
        vm.expectRevert(ScientificFundOracle.TransferFailed.selector);
        attacker.release(0);
    }

    // ---------- oracle ----------

    function test_Oracle_Rules() public view {
        assertTrue(oracle.validateMilestone(projectOwner, 0, "QmX", 1));
        assertFalse(oracle.validateMilestone(address(0), 0, "QmX", 1));
        assertFalse(oracle.validateMilestone(projectOwner, 0, "", 1));
        assertFalse(oracle.validateMilestone(projectOwner, 0, "QmX", 0));
    }

    // ---------- fuzz ----------

    function testFuzz_Contribute(uint96 amount) public {
        vm.assume(amount > 0);
        deal(stranger, amount);
        vm.prank(stranger);
        fund.contribute{value: amount}();
        assertEq(fund.totalRaised(), amount);
        assertEq(address(fund).balance, amount);
    }
}
