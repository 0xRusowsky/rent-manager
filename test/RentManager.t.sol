// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import "src/RentManager.sol";

contract ContractTest is Test {
    MockERC721 nft;
    RentManager rent;
    address owner;
    address rentee;
    address keeper;

    function setUp() public {
        nft = new MockERC721("Non-Fungible Token A", "NFTA");
        rent = new RentManager();

        owner = vm.addr(1);
        vm.deal(owner, 100 ether);
        vm.label(owner, "Owner");
        rentee = vm.addr(2);
        vm.deal(rentee, 100 ether);
        vm.label(rentee, "Rentee");
        keeper = vm.addr(3);
        vm.label(keeper, "Keeper");
        
        nft.mint(owner, 1);
        nft.mint(owner, 2);
    }

    function testDepositAndWithdraw() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);

        assertTrue(nft.ownerOf(1) == address(rent));
        assertFalse(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        
        rent.withdraw(address(nft), 1);

        assertTrue(nft.ownerOf(1) == owner);
        assertTrue(rent.ownerOf(address(nft), 1) == address(0));
        assertTrue(rent.deadlineOf(address(nft), 1) == 0);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        vm.stopPrank();
    }

    function testDelegate() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.delegate(address(nft), 1, rentee, 123 weeks);        
        vm.stopPrank();

        //Start Rent
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0 ether);
        assertTrue(owner.balance == 100 ether);
        assertTrue(rentee.balance == 100 ether);
        vm.stopPrank();
    }

    function testStartRent() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        //Start Rent
        vm.startPrank(rentee);
        rent.startRent{value: 0.1 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 1 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.1 ether);
        assertTrue(owner.balance == 100.099 ether);
        assertTrue(rentee.balance == 99.9 ether);
        vm.stopPrank();
    }

    function testStartRentWIthTwoDifferentNFTs() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        nft.approve(address(rent), 2);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);
        rent.deposit(address(nft), 2, 123 weeks, 0.1 ether);
        vm.stopPrank();

        //Start Rent tokenId = 1
        vm.startPrank(rentee);
        rent.startRent{value: 0.1 ether}(address(nft), 1);
        address deleg1 = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg1);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 1 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.1 ether);
        assertTrue(owner.balance == 100.099 ether);
        assertTrue(rentee.balance == 99.9 ether);
        
        //Start Rent tokenId = 2
        rent.startRent{value: 0.1 ether}(address(nft), 2);
        address deleg2 = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(2) == deleg2);
        assertTrue(rent.isRented(address(nft), 2));
        assertTrue(rent.ownerOf(address(nft), 2) == owner);
        assertTrue(rent.deadlineOf(address(nft), 2) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 2) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 2) == rentee);
        assertTrue(rent.endDateOf(address(nft), 2) == 1 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 2) == 0.1 ether);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);
        vm.stopPrank();

        assertTrue(address(deleg1) == address(deleg2));
    }

        function testStartRentRequirements() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        //Start Rent
        vm.startPrank(rentee);
        vm.expectRevert("LOW_FEE");
        rent.startRent(address(nft), 1);

        vm.expectRevert("WRONG_FEE");
        rent.startRent{value: 0.15 ether}(address(nft), 1);

        vm.expectRevert("NOT_RENTABLE");
        rent.startRent{value: 0.1 ether}(address(nft), 2);

        vm.expectRevert("OVER_DEADLINE");
        rent.startRent{value: 124 * 0.1 ether}(address(nft), 1);

        rent.startRent{value: 0.1 ether}(address(nft), 1);
        vm.expectRevert("ALREADY_RENTED");
        rent.startRent{value: 0.1 ether}(address(nft), 1);
        vm.stopPrank();
    }

    function testExtendRent() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.startPrank(rentee);
        rent.startRent{value: 0.1 ether}(address(nft), 1);

        // Extend Rent
        rent.extendRent{value: 0.1 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 2 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.2 ether);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);
        vm.stopPrank();
    }

        function testExtendRentRequirements() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.startPrank(rentee);
        rent.startRent{value: 0.1 ether}(address(nft), 1);
        
        // Extend Rent
        vm.expectRevert("WRONG_FEE");
        rent.extendRent{value: 0.15 ether}(address(nft), 1);

        vm.expectRevert("OVER_DEADLINE");
        rent.extendRent{value: 124 * 0.1 ether}(address(nft), 1);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("NOT_RENTEE");
        rent.extendRent{value: 0.1 ether}(address(nft), 1);
        vm.stopPrank();
    }

    function testEndRentEarly() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.prank(rentee);
        rent.startRent{value: 0.2 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 2 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.2 ether);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);

        //Elapse 1 week
        vm.warp(1 + 1 weeks);

        //End Rent Early
        (, uint256 payback) = rent.paybackHelper(address(nft), 1);
        vm.prank(owner);
        rent.endRent{value: payback}(address(nft), 1);
        assertTrue(nft.ownerOf(1) == owner);
        assertFalse(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == address(0));
        assertTrue(rent.deadlineOf(address(nft), 1) == 0);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        assertTrue(rent.endDateOf(address(nft), 1) == 0);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0);
        assertTrue(owner.balance == 100.1 ether);
        assertTrue(rentee.balance == 99.9 ether);
        vm.stopPrank();
    }

    function testEndRentKeeper() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.prank(rentee);
        rent.startRent{value: 0.2 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 2 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.2 ether);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);

        //Elapse 2 weeks
        vm.warp(2 + 2 weeks);

        //End Rent
        vm.prank(keeper);
        rent.endRent(address(nft), 1);
        assertTrue(nft.ownerOf(1) == address(rent));
        assertFalse(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        assertTrue(rent.endDateOf(address(nft), 1) == 0);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);
        assertTrue(keeper.balance == 0.002 ether);
        vm.stopPrank();
    }

    function testEndRentKeeperAfterDeadline() public {
        vm.startPrank(owner);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 123 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.prank(rentee);
        rent.startRent{value: 0.2 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == owner);
        assertTrue(rent.deadlineOf(address(nft), 1) == 123 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == rentee);
        assertTrue(rent.endDateOf(address(nft), 1) == 2 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.2 ether);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);

        //Elapse until deadline
        vm.warp(1 + 123 weeks);

        //End Rent
        vm.prank(keeper);
        rent.endRent(address(nft), 1);
        assertTrue(nft.ownerOf(1) == owner);
        assertFalse(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == address(0));
        assertTrue(rent.deadlineOf(address(nft), 1) == 0);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        assertTrue(rent.endDateOf(address(nft), 1) == 0);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0);
        assertTrue(owner.balance == 100.198 ether);
        assertTrue(rentee.balance == 99.8 ether);
        assertTrue(keeper.balance == 0.002 ether);
        vm.stopPrank();
    }

}