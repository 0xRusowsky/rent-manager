// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "solmate/tokens/ERC721.sol";
import "./DelegationManager.sol";

/// @notice Implementation of a peer-to-peer NFT rent manager contract
/// @author 0xruswowsky (https://github.com/0xRusowsky/rent-manager/blob/main/src/RentManager.sol)
contract RentManager {

    /// ----- EVENTS --------------------------------------------------

    event Deposit(address indexed owner, address indexed contract_, uint256 tokenId, uint256 deadline, uint256 weeklyFee);
    event Withdraw(address indexed contract_, uint256 indexed tokenId);
    event RentStart(address indexed contract_, uint256 indexed tokenId, address indexed rentee, uint256 rentedWeeks);
    event RentExtend(address indexed contract_, uint256 indexed tokenId, address indexed rentee, uint256 rentedWeeks);
    event RentEnd(address indexed contract_, uint256 indexed tokenId);

    /// ----- RENT STORAGE --------------------------------------------

    /// @notice Keepers get 1% of the fees for closing a rent
    uint256 constant KEEPER_FEE = 1;

    /// @notice Relevant rent terms and current status
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

    /// @notice Mapping between ERC721 contract and its DelegationManager contract
    mapping(address => DelegationManager) internal _getDelegation;

    /// @notice Mapping between ERC721 contract and its RentData
    mapping(address => mapping(uint256 => RentData)) internal _getRent;

    /// @notice Return the depositor of an item, which is considered to be its owner
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function ownerOf(address contract_, uint256 tokenId) public view returns(address) {
        return _getRent[contract_][tokenId].owner;
    }

    /// @notice Return the weekly fees to rent an item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function weeklyFeeOf(address contract_, uint256 tokenId) public view returns(uint256) {
        return _getRent[contract_][tokenId].weeklyFee;
    }

    /// @notice Return the rent deadline from a deposited item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function deadlineOf(address contract_, uint256 tokenId) public view returns(uint256) {
        return _getRent[contract_][tokenId].deadline;
    }

    /// @notice Return the DelegationManager contract address from a given contract
    /// @param contract_ ERC721 contract address
    function getDelegation(address contract_) public view returns(address) {
        return address(_getDelegation[contract_]);
    }

    /// @notice Return whether a token from a given item is rented (true) or not (false)
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function isRented(address contract_, uint256 tokenId) public view returns(bool) {
        return _getRent[contract_][tokenId].rentee != address(0) ? true : false;
    }

    /// @notice Return the rentee of an item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function renteeOf(address contract_, uint256 tokenId) public view returns(address) {
        return block.timestamp < deadlineOf(contract_, tokenId) ? _getRent[contract_][tokenId].rentee : address(0);
    }

    /// @notice Return the total amount of fees payed to rent an item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function payedFeesOf(address contract_, uint256 tokenId) public view returns(uint256) {
        return _getRent[contract_][tokenId].payedFee;
    }

    /// @notice Return the expected ending date of a rent
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function endDateOf(address contract_, uint256 tokenId) public view returns(uint256) {
        RentData memory rent = _getRent[contract_][tokenId];
        return rent.weeklyFee > 0 ? rent.startTime + (rent.payedFee / rent.weeklyFee) * 1 weeks : rent.deadline;
    }
    

    /// ----- DEPOSIT/WITHDRAW LOGIC ----------------------------------

    /// @notice Give ownership of an item to the RentManager
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    /// @param deadline Max timestamp before the owner wants to get back ownership of the item 
    /// @param weeklyFee Required weekly fee to rent the item
    function deposit(address contract_, uint256 tokenId, uint256 deadline, uint256 weeklyFee) external {
        IERC721 nft = IERC721(contract_);
        nft.transferFrom(msg.sender, address(this), tokenId);
        _getRent[contract_][tokenId] = RentData(msg.sender, deadline, weeklyFee, address(0), 0, 0);

        emit Deposit(msg.sender, contract_, tokenId, deadline, weeklyFee);
    }

    /// @notice Give back ownership of an item to its owner. Only usable if the item is not rented.
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function withdraw(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];
        require(rent.owner == msg.sender, "NOT_OWNER");
        require(rent.rentee == address(0), "IS_RENTED");

        _withdraw(rent.owner, contract_, tokenId);
    }

    /// ----- RENT LOGIC ----------------------------------------------

    /// @notice Start a new rent for an item in custody of the RentManager
    /// @dev Gives ownership of the asset to the DelegationManager
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function startRent(address contract_, uint256 tokenId) external payable {
        ERC721 nft = ERC721(contract_);
        RentData memory rent = _getRent[contract_][tokenId];

        require(msg.value > 0, "NO_FEE");
        require(rent.weeklyFee == 0 || msg.value % rent.weeklyFee == 0, "WRONG_FEE");
        require(rent.owner != address(0), "NOT_RENTABLE");
        require(rent.rentee == address(0), "ALREADY_RENTED");
        require(rent.deadline > block.timestamp + 1 weeks * (rent.payedFee + msg.value) / rent.weeklyFee, "OVER_DEADLINE");
        
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

    /// @notice Extend the rent period by paying more fees
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function extendRent(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];

        require(msg.value % rent.weeklyFee == 0, "WRONG_FEE");
        require(rent.rentee == msg.sender, "NOT_RENTEE");
        require(rent.deadline > rent.startTime + 1 weeks * (rent.payedFee + msg.value) / rent.weeklyFee, "OVER_DEADLINE");
        
        uint256 payedFee = rent.payedFee + msg.value;
        _getRent[contract_][tokenId].payedFee = payedFee;

        (bool success, ) = rent.owner.call{value: msg.value * (100 - KEEPER_FEE) / 100}("");
        require(success);

        emit RentExtend(contract_, tokenId, msg.sender, payedFee / rent.weeklyFee);
    }

    /// @notice End an ongoing rent
    ///         Owners can redeem before endDate by paying the fees back to the renter
    ///         Keepers can call this function to end finished rents and book a small profit
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function endRent(address contract_, uint256 tokenId) public payable {
        RentData memory rent = _getRent[contract_][tokenId];
        require(rent.rentee != address(0));

        if (block.timestamp > rent.deadline) {
            _endRent(rent.owner, contract_, tokenId, true);

            (bool success, ) = msg.sender.call{value: rent.payedFee * KEEPER_FEE / 100}("");
            require(success);

        } else if (block.timestamp > rent.startTime + 1 weeks * rent.payedFee / rent.weeklyFee) {
            _endRent(rent.owner, contract_, tokenId, false);

            (bool success, ) = msg.sender.call{value: rent.payedFee * KEEPER_FEE / 100}("");
            require(success);

        } else {
            require(rent.owner == msg.sender, "NOT_OWNER");

            _endRent(rent.owner, contract_, tokenId, true);

            (uint256 payback, uint256 value) = _paybackHelper(rent);
            require(msg.value == value, "INVALID_PAYBACK");

            (bool success, ) = rent.rentee.call{value: payback}("");
            require(success); 
        }

        emit RentEnd(contract_, tokenId);
    }

    /// ----- HELPER FUNCTIONS ----------------------------------------

    /// @notice Get the required payback to end a rent before closure
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function paybackHelper(address contract_, uint256 tokenId) public view returns (uint256, uint256) {
        RentData memory rent = _getRent[contract_][tokenId];
        (uint256 payback, uint256 value) = _paybackHelper(rent);
        return (payback, value);

    }

    /// @notice Internal function to get the required payback to end a rent before closure
    /// @param rent Relevant rent data
    function _paybackHelper(RentData memory rent) public view returns (uint256, uint256) {
        uint256 elapsedWeeks = (block.timestamp - rent.startTime) / 1 weeks;
        uint256 payback = rent.payedFee - elapsedWeeks * rent.weeklyFee;

        return (payback, payback - rent.payedFee * KEEPER_FEE / 100);
    }

    /// ----- INTERNAL RENT LOGIC -------------------------------------

    /// @notice Give ownership of an item back to its owner
    /// @param owner Original owner of the item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function _withdraw(address owner, address contract_, uint256 tokenId) internal {
        delete _getRent[contract_][tokenId];

        IERC721 nft = IERC721(contract_);
        nft.transferFrom(address(this), owner, tokenId);
    }

    /// @notice Reclaim ownership of an item by transfering it away from the DelegationManager
    /// @param owner Original owner of the item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    /// @param isOver Whether the item is sent back to its owner (true) or not (false)
    function _endRent(address owner, address contract_, uint256 tokenId, bool isOver) internal {
        DelegationManager delegation = _getDelegation[contract_];
        delegation.withdraw(tokenId);

        delete _getRent[contract_][tokenId].rentee;
        delete _getRent[contract_][tokenId].startTime;
        delete _getRent[contract_][tokenId].payedFee;

        if (isOver) _withdraw(owner, contract_, tokenId);
    }
}