// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import "src/RentManager.sol";

contract ContractTest is Test {
    MockERC721 nft;
    RentManager rent;
    address alice;
    address bob;

    function setUp() public {
        nft = new MockERC721("Non-Fungible Token", "NFT");
        rent = new RentManager();

        alice = vm.addr(1);
        vm.deal(alice, 10 ether);
        vm.label(alice, "Alice");
        bob = vm.addr(2);
        vm.deal(bob, 10 ether);
        vm.label(bob, "Bob");
        
        nft.mint(alice, 1);
    }

    function testDepositAndWithdraw() public {
        vm.startPrank(alice);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 1234 weeks, 0.1 ether);

        assertTrue(nft.ownerOf(1) == address(rent));
        assertFalse(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == alice);
        assertTrue(rent.deadlineOf(address(nft), 1) == 1234 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        
        rent.withdraw(address(nft), 1);

        assertTrue(nft.ownerOf(1) == alice);
        assertTrue(rent.ownerOf(address(nft), 1) == address(0));
        assertTrue(rent.deadlineOf(address(nft), 1) == 0);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0);
        assertTrue(rent.renteeOf(address(nft), 1) == address(0));
        vm.stopPrank();
    }

    function testStartRent() public {
        vm.startPrank(alice);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 1234 weeks, 0.1 ether);        
        vm.stopPrank();

        //Start Rent
        vm.startPrank(bob);
        rent.startRent{value: 0.1 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == alice);
        assertTrue(rent.deadlineOf(address(nft), 1) == 1234 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.endDateOf(address(nft), 1) == 1 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == bob);
        assertTrue(alice.balance == 10.099 ether);
        assertTrue(bob.balance == 9.9 ether);
        vm.stopPrank();
    }

    function testExtendRent() public {
        vm.startPrank(alice);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 1234 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.startPrank(bob);
        rent.startRent{value: 0.1 ether}(address(nft), 1);
        rent.extendRent{value: 0.1 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == alice);
        assertTrue(rent.deadlineOf(address(nft), 1) == 1234 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.endDateOf(address(nft), 1) == 2 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.2 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == bob);
        assertTrue(alice.balance == 10.198 ether);
        assertTrue(bob.balance == 9.8 ether);
        vm.stopPrank();
    }

    function testEndRent() public {
        vm.startPrank(alice);
        nft.approve(address(rent), 1);
        rent.deposit(address(nft), 1, 1234 weeks, 0.1 ether);        
        vm.stopPrank();

        vm.startPrank(bob);
        rent.startRent{value: 0.2 ether}(address(nft), 1);
        rent.extendRent{value: 0.1 ether}(address(nft), 1);
        address deleg = rent.getDelegation(address(nft));

        assertTrue(nft.ownerOf(1) == deleg);
        assertTrue(rent.isRented(address(nft), 1));
        assertTrue(rent.ownerOf(address(nft), 1) == alice);
        assertTrue(rent.deadlineOf(address(nft), 1) == 1234 weeks);
        assertTrue(rent.weeklyFeeOf(address(nft), 1) == 0.1 ether);
        assertTrue(rent.endDateOf(address(nft), 1) == 2 weeks + 1);
        assertTrue(rent.payedFeesOf(address(nft), 1) == 0.2 ether);
        assertTrue(rent.renteeOf(address(nft), 1) == bob);
        vm.stopPrank();
    }

}