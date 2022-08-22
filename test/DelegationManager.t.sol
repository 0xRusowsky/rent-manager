// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import "src/DelegationManager.sol";

contract ContractTest is Test {
    MockERC721 nft;
    DelegationManager deleg;
    address alice;
    address bob;

    function setUp() public {
        nft = new MockERC721("Non-Fungible Token", "NFT");
        deleg = new DelegationManager(address(nft), nft.name(), nft.symbol());

        alice = vm.addr(1);
        bob = vm.addr(2);
        
        nft.mint(alice, 1);
    }

    function testDelegation() public {
        vm.startPrank(alice);
        nft.approve(address(deleg), 1);
        deleg.deposit(alice, bob, 1);

        assertTrue(nft.ownerOf(1) == address(deleg));
        assertTrue(deleg.realOwnerOf(1) == alice);
        assertTrue(deleg.ownerOf(1) == bob);

        deleg.withdraw(1);

        assertTrue(nft.ownerOf(1) == alice);
        assertTrue(deleg.realOwnerOf(1) == address(0));
        vm.expectRevert("NOT_MINTED");
        deleg.ownerOf(1);
        
        vm.stopPrank();
    }

    function testAccessControl() public {
        vm.startPrank(alice);
        nft.approve(address(deleg), 1);
        deleg.deposit(alice, bob, 1);
        vm.stopPrank();

        vm.prank(bob);        
        vm.expectRevert("UNAUTHORIZED");
        deleg.withdraw(1);
    }
}