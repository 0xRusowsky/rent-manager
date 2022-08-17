// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "solmate/tokens/ERC721.sol";
import "./WrappedERC721.sol";

contract Rentable {

    struct rentalData {
        address owner;
        address rentee;
        uint256 expiry;
        uint256 fee;
    }

    mapping(address => WrappedERC721) internal _getWrapped;

    mapping(address => mapping(uint256 => rentalData)) internal _getRental;

    /// ----- RENTAL STORAGE --------------------------------------------------

    function getWrapped(address collection) public view returns(address) {
        return address(_getWrapped[collection]);
    }

    function expiryOf(address collection, uint256 id) public view returns(uint256) {
        return _getRental[collection][id].expiry;
    }

    function feeOf(address collection, uint256 id) public view returns(uint256) {
        return _getRental[collection][id].fee;
    }

    function ownerOf(address collection, uint256 id) public view returns(address) {
        return _getRental[collection][id].owner;
    }

    function renteeOf(address collection, uint256 id) public view returns(address) {
        return block.timestamp < expiryOf(collection, id) ? _getRental[collection][id].rentee : address(0);
    }
    

    /// ----- RENTAL LOGIC --------------------------------------------------

    function deposit(address collection, uint256 id, uint256 maxExpiry, uint256 fee) external {
        IERC721 nft = IERC721(collection);
        nft.transferFrom(msg.sender, address(this), id);
        _getRental[collection][id] = rentalData(msg.sender, address(0), maxExpiry, fee);

        //emit Deposit(owner, collection, id, maxExpiry, fee);
    }

    function withdrawl(address collection, uint256 id) external {
        address owner = _getRental[collection][id].owner;
        
        require(msg.sender == owner, "NOT_OWNER");

        IERC721 nft = IERC721(collection);
        nft.transferFrom(address(this), owner, id);

        //emit Withdrawl(owner, collection, id);
    }

    function startRental(address collection, uint256 id) external payable {
        rentalData memory rent = _getRental[collection][id];
        require(rent.fee == msg.value, "WRONG_FEE");
        require(rent.owner != address(0), "NOT_RENTABLE");
        require(rent.rentee == address(0), "ALREADY_RENTED");
        require(rent.expiry > block.timestamp, "EXPIRED");

        (bool success, ) = rent.owner.call{value: rent.fee}("");
        require(success);

        if (address(_getWrapped[collection]) == address(0)) {
            ERC721 nft = ERC721(collection);
            WrappedERC721 newWrapped = new WrappedERC721(collection, nft.name(), nft.symbol());

            _getWrapped[collection] = newWrapped;
            newWrapped.wrap(msg.sender, id);
        } else {        
            WrappedERC721 wrapped = _getWrapped[collection];
            wrapped.wrap(msg.sender, id);

            rent.rentee = msg.sender;
        }
    }

    function endRental(address collection, uint256 id) external payable {
        require(_getRental[collection][id].owner == msg.sender, "NOT_OWNER");

        WrappedERC721 wrapped = _getWrapped[collection];
        wrapped.unwrap(id);

        delete _getRental[collection][id];
        
        IERC721 nft = IERC721(collection);
        nft.transferFrom(address(this), msg.sender, id);
    }
}