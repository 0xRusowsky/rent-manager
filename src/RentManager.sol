// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "solmate/tokens/ERC721.sol";
import "./DelegationManager.sol";

contract RentManager {

    event Deposit(address indexed owner, address indexed contract_, uint256 tokenId, uint256 deadline, uint256 weeklyFee);
    event Withdraw(address indexed contract_, uint256 indexed tokenId);
    event RentStart(address indexed contract_, uint256 indexed tokenId, address indexed rentee, uint256 rentedWeeks);
    event RentExtend(address indexed contract_, uint256 indexed tokenId, address indexed rentee, uint256 rentedWeeks);
    event RentEnd(address indexed contract_, uint256 indexed tokenId);

    // Keepers get 1% of the fees for closing a rent
    uint256 constant KEEPER_FEE = 1;

    struct RentData {
        // Rent terms
        address owner;
        uint256 deadline;
        uint256 weeklyFee;
        // Rent status
        address rentee;
        uint256 startTime;
        uint256 payedFee;
    }

    mapping(address => DelegationManager) internal _getDelegation;

    mapping(address => mapping(uint256 => RentData)) internal _getRent;

    /// ----- RENT STORAGE --------------------------------------------------

    function getDelegation(address contract_) public view returns(address) {
        return address(_getDelegation[contract_]);
    }

    function isRented(address contract_, uint256 tokenId) public view returns(bool) {
        return _getRent[contract_][tokenId].rentee != address(0) ? true : false;
    }

    function deadlineOf(address contract_, uint256 tokenId) public view returns(uint256) {
        return _getRent[contract_][tokenId].deadline;
    }

    function weeklyFeeOf(address contract_, uint256 tokenId) public view returns(uint256) {
        return _getRent[contract_][tokenId].weeklyFee;
    }

    function ownerOf(address contract_, uint256 tokenId) public view returns(address) {
        return _getRent[contract_][tokenId].owner;
    }

    function renteeOf(address contract_, uint256 tokenId) public view returns(address) {
        return block.timestamp < deadlineOf(contract_, tokenId) ? _getRent[contract_][tokenId].rentee : address(0);
    }

    function payedFeesOf(address contract_, uint256 tokenId) public view returns(uint256) {
        return _getRent[contract_][tokenId].payedFee;
    }

    function endDateOf(address contract_, uint256 tokenId) public view returns(uint256) {
        RentData memory rent = _getRent[contract_][tokenId];
        return rent.startTime + (rent.payedFee / rent.weeklyFee) * 1 weeks;
    }
    

    /// ----- RENT LOGIC --------------------------------------------------

    function deposit(address contract_, uint256 tokenId, uint256 deadline, uint256 weeklyFee) external {
        IERC721 nft = IERC721(contract_);
        nft.transferFrom(msg.sender, address(this), tokenId);
        _getRent[contract_][tokenId] = RentData(msg.sender, deadline, weeklyFee, address(0), 0, 0);

        emit Deposit(msg.sender, contract_, tokenId, deadline, weeklyFee);
    }

    function withdraw(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];
        require(rent.owner == msg.sender, "NOT_OWNER");
        require(rent.rentee == address(0), "IS_RENTED");

        delete _getRent[contract_][tokenId];
        
        IERC721 nft = IERC721(contract_);
        nft.transferFrom(address(this), rent.owner, tokenId);
    }

    function startRent(address contract_, uint256 tokenId) external payable {
        ERC721 nft = ERC721(contract_);
        RentData memory rent = _getRent[contract_][tokenId];

        require(msg.value > 0, "NO_FEE");
        require(msg.value % rent.weeklyFee == 0, "WRONG_FEE");
        require(rent.owner != address(0), "NOT_RENTABLE");
        require(rent.rentee == address(0), "ALREADY_RENTED");
        require(rent.deadline > block.timestamp, "EXPIRED");
        require(rent.deadline > 1 weeks * (rent.payedFee + msg.value) / rent.weeklyFee, "OVER_DEADLINE");
        
        _getRent[contract_][tokenId].rentee = msg.sender;
        _getRent[contract_][tokenId].payedFee = msg.value;
        _getRent[contract_][tokenId].startTime = block.timestamp;

        (bool success, ) = rent.owner.call{value: msg.value * (100 - KEEPER_FEE) / 100}("");
        require(success);

        if (address(_getDelegation[contract_]) == address(0)) {
            DelegationManager newDelegation = new DelegationManager(contract_, nft.name(), nft.symbol());
            _getDelegation[contract_] = newDelegation;

            nft.approve(address(newDelegation), tokenId);
            newDelegation.deposit(rent.owner, msg.sender, tokenId);
        } else {        
            DelegationManager delegation = _getDelegation[contract_];

            nft.approve(address(delegation), tokenId);
            delegation.deposit(rent.owner, msg.sender, tokenId);
        }

        emit RentStart(contract_, tokenId, msg.sender, msg.value / rent.weeklyFee);
    }

    function extendRent(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];

        require(msg.value % rent.weeklyFee == 0, "WRONG_FEE");
        require(rent.rentee == msg.sender, "NOT_RENTEE");
        require(rent.deadline > block.timestamp, "EXPIRED");
        require(rent.deadline > 1 weeks * (rent.payedFee + msg.value) / rent.weeklyFee, "OVER_DEADLINE");
        
        uint256 payedFee = rent.payedFee + msg.value;
        _getRent[contract_][tokenId].payedFee = payedFee;

        (bool success, ) = rent.owner.call{value: msg.value * (100 - KEEPER_FEE) / 100}("");
        require(success);

        emit RentExtend(contract_, tokenId, msg.sender, payedFee / rent.weeklyFee);
    }

    function endRent(address contract_, uint256 tokenId) public payable {
        RentData memory rent = _getRent[contract_][tokenId];
        require(rent.rentee != address(0));

        if (block.timestamp > rent.deadline || block.timestamp > 1 weeks * rent.payedFee / rent.weeklyFee) {
            _endRent(rent.owner, contract_, tokenId);

            (bool success, ) = msg.sender.call{value: rent.payedFee * KEEPER_FEE / 100}("");
            require(success);

        } else {
            require(rent.owner == msg.sender, "NOT_OWNER");

            _endRent(rent.owner, contract_, tokenId);

            (uint256 payback, uint256 value) = paybackHelper(rent);
            require(msg.value == value, "INVALID_PAYBACK");

            (bool success, ) = rent.rentee.call{value: payback}("");
            require(success); 
        }

        emit RentEnd(contract_, tokenId);
    }

    function paybackHelper(RentData memory rent) public view returns (uint256, uint256) {
        uint256 elapsedWeeks = (block.timestamp - rent.startTime) / 1 weeks;
        uint256 payback = rent.payedFee - elapsedWeeks * rent.weeklyFee;

        return (payback, payback - rent.payedFee * KEEPER_FEE / 100);
    }

    function _endRent(address owner, address contract_, uint256 tokenId) internal {
        DelegationManager delegation = _getDelegation[contract_];
        delegation.withdraw(tokenId);

        delete _getRent[contract_][tokenId];
        
        IERC721 nft = IERC721(contract_);
        nft.transferFrom(address(this), owner, tokenId);
    }
}