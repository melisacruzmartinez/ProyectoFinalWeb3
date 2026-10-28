// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ScientificFundOracle} from "../contracts/ScientificFundOracle.sol";
import {ScientificOracle} from "../contracts/ScientificOracle.sol";

contract ScientificFundOracleFuzzTest is Test {
    ScientificFundOracle internal fund;
    ScientificOracle internal oracle;

    address internal projectOwner = makeAddr("projectOwner");
    address internal auditor1 = makeAddr("auditor1");
    address internal auditor2 = makeAddr("auditor2");
    address internal auditor3 = makeAddr("auditor3");
    address internal donor = makeAddr("donor");

    function setUp() public {
        address[] memory list = new address[](3);
        list[0] = auditor1;
        list[1] = auditor2;
        list[2] = auditor3;

        oracle = new ScientificOracle();
        fund = new ScientificFundOracle(projectOwner, list, address(oracle));
        deal(donor, 1_000 ether);
    }

    function _prepare(uint256 raised, uint256 amount, bool a1, bool a2, bool a3) internal returns (uint256 id) {
        vm.prank(donor);
        fund.contribute{value: raised}();
        vm.prank(projectOwner);
        id = fund.createMilestone("Fase 1: prototipo", "QmEvidencia001", amount);

        vm.prank(auditor1);
        fund.voteMilestone(id, a1);
        vm.prank(auditor2);
        fund.voteMilestone(id, a2);
        vm.prank(auditor3);
        fund.voteMilestone(id, a3);

        fund.validateMilestone(id);
    }

    function testFuzz_Release_PaysExactAmount(uint96 raised, uint96 amount) public {
        raised = uint96(bound(raised, 1, 500 ether));
        amount = uint96(bound(amount, 1, raised));
        uint256 id = _prepare(raised, amount, true, true, false);

        vm.prank(projectOwner);
        fund.releaseMilestone(id);

        assertEq(projectOwner.balance, amount);
        assertEq(address(fund).balance, uint256(raised) - amount);
        assertEq(fund.totalReleased(), amount);
        assertTrue(fund.isMilestoneReleased(id));
    }

    function testFuzz_RevertWhen_AmountExceedsBalance(uint96 raised, uint96 amount) public {
        raised = uint96(bound(raised, 1, 500 ether));
        amount = uint96(bound(amount, uint256(raised) + 1, type(uint96).max));
        uint256 id = _prepare(raised, amount, true, true, true);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.InsufficientBalance.selector, raised, amount));
        fund.releaseMilestone(id);
    }

    function testFuzz_Release_RequiresMajority(bool a1, bool a2, bool a3) public {
        uint256 id = _prepare(5 ether, 1 ether, a1, a2, a3);
        uint256 votesFor = (a1 ? 1 : 0) + (a2 ? 1 : 0) + (a3 ? 1 : 0);

        if (votesFor < fund.approvalsRequired()) {
            vm.expectRevert(abi.encodeWithSelector(ScientificFundOracle.NoApproval.selector, votesFor, 2));
        }
        vm.prank(projectOwner);
        fund.releaseMilestone(id);

        assertEq(fund.isMilestoneReleased(id), votesFor >= 2);
    }

    function testFuzz_Contribute_ManyDonors(address[5] memory donors, uint64[5] memory amounts) public {
        uint256 total;
        for (uint256 i = 0; i < donors.length; i++) {
            vm.assume(donors[i].code.length == 0 && uint160(donors[i]) > 10);
            uint256 amount = bound(amounts[i], 1, 10 ether);
            deal(donors[i], amount);

            uint256 before = fund.contributions(donors[i]);
            vm.prank(donors[i]);
            fund.contribute{value: amount}();

            assertEq(fund.contributions(donors[i]), before + amount);
            total += amount;
        }
        assertEq(fund.totalRaised(), total);
        assertEq(address(fund).balance, total);
    }

    function testFuzz_Oracle_Rules(address project, uint256 milestoneId, string calldata ipfsHash, uint256 amount)
        public
        view
    {
        bool expected = project != address(0) && bytes(ipfsHash).length != 0 && amount != 0;
        assertEq(oracle.validateMilestone(project, milestoneId, ipfsHash, amount), expected);
    }
}
