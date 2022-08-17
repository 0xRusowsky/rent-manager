// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import "src/Rentable.sol";
import "src/WrappedERC721.sol";

contract ContractTest is Test {
    MockERC721 nft;
    Rentable rentable;
    address alice;
    address bob;

    function setUp() public {
        nft = new MockERC721("Token", "TKN");
        rentable = new Rentable();

        alice = vm.addr(1);
        vm.label(alice, "alice");
        vm.deal(alice, 10 ether);

        bob = vm.addr(2);
        vm.label(bob, "bob");
        vm.deal(bob, 10 ether);

        nft.mint(alice, 1);
        nft.mint(alice, 2);
    }

    function testRent() public {
        vm.startPrank(alice);
        nft.approve(address(rentable), 1);
        rentable.deposit(address(nft), 1, 1234, 0.1 ether);
        nft.approve(address(rentable), 2);
        rentable.deposit(address(nft), 2, 1234, 0.2 ether);

        assert(nft.ownerOf(1) == address(rentable));
        assert(rentable.ownerOf(address(nft), 1) == alice);
        vm.stopPrank();

        vm.startPrank(bob);
        emit log_named_uint("Bob balance before rent", bob.balance);
        emit log_named_uint("Alice balance before rent", alice.balance);
        emit log_uint(block.timestamp);
        rentable.startRental{value: 0.1 ether}(address(nft), 1);
        emit log_named_uint("Bob balance after rent", bob.balance);
        emit log_named_uint("Alice balance after rent", alice.balance);

        WrappedERC721 wrapped = WrappedERC721(rentable.getWrapped(address(nft)));
        assert(nft.ownerOf(1) == address(wrapped));
        assert(wrapped.ownerOf(1) == bob);
        assert(wrapped.balanceOf(bob) == 1);

        emit log_named_uint("Bob balance before rent", bob.balance);
        emit log_named_uint("Alice balance before rent", alice.balance);
        emit log_uint(block.timestamp);
        rentable.startRental{value: 0.2 ether}(address(nft), 2);
        emit log_named_uint("Bob balance after rent", bob.balance);
        emit log_named_uint("Alice balance after rent", alice.balance);
        vm.stopPrank();

        assert(wrapped.balanceOf(bob) == 2);

        vm.startPrank(alice);
        rentable.endRental(address(nft), 1);
        assert(nft.ownerOf(1) == alice);
        assert(rentable.ownerOf(address(nft), 1) == address(0));
        assert(wrapped.balanceOf(bob) == 1);
        vm.stopPrank();
    }
}