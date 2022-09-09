// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "solmate/tokens/ERC721.sol";
import "./DelegationManager.sol";

/// @notice Implementation of a peer-to-peer NFT rent manager contract
/// @author 0xruswowsky (https://github.com/0xRusowsky/rent-manager/blob/main/src/RentManager.sol)
contract RentManager {

    /// ----- ERRORS --------------------------------------------------

    error NotOwner();
    error NotRentable();
    error OnlyRentableOTC(address rentableBy);
    error OverDeadline();    
    error RentedItem();
    error WrongPaymentAmount();

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
        return _getRent[contract_][tokenId].startTime != 0 ? true : false;
    }

    /// @notice Return the rentee of an item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function renteeOf(address contract_, uint256 tokenId) public view returns(address) {
        RentData memory rent = _getRent[contract_][tokenId];
        return rent.startTime != 0 ? rent.rentee : address(0);
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
        return rent.weeklyFee == 0 ? rent.deadline : rent.startTime + (rent.payedFee / rent.weeklyFee) * 1 weeks;
    }


    /// ----- DELEGATION LOGIC ----------------------------------------

    /// @notice Delegate an item by starting a free rent to the desired delegatee
    ///         Gives ownership of the item to the RentManager
    ///         The RentManager gives ownership of the item to the DelegationManager
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item 
    /// @param to The address to which the item is delegated
    /// @param deadline Max timestamp before the owner wants to get back ownership of the item
    function delegate(address contract_, uint256 tokenId, address to, uint256 deadline) external {
        IERC721 nft = IERC721(contract_);
        nft.transferFrom(msg.sender, address(this), tokenId);
        _getRent[contract_][tokenId] = RentData(msg.sender, deadline, 0, address(0), 0, 0);

        _startRent(contract_, tokenId, msg.sender, to, 0);

        emit RentStart(contract_, tokenId, to, 0);
    }


    /// ----- DEPOSIT/WITHDRAW LOGIC ----------------------------------

    /// @notice Give ownership of an item to the RentManager so that it can be rented by anyone
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

    /// @notice Give ownership of an item to the RentManager so that it can only be rented by a specified address
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    /// @param rentee Address allowed to rent the deposited item
    /// @param deadline Max timestamp before the owner wants to get back ownership of the item 
    /// @param weeklyFee Required weekly fee to rent the item
    function depositOTC(address contract_, uint256 tokenId, address rentee, uint256 deadline, uint256 weeklyFee) external {
        IERC721 nft = IERC721(contract_);
        nft.transferFrom(msg.sender, address(this), tokenId);
        _getRent[contract_][tokenId] = RentData(msg.sender, deadline, weeklyFee, rentee, 0, 0);

        emit Deposit(msg.sender, contract_, tokenId, deadline, weeklyFee);
    }

    /// @notice Give back ownership of an item to its owner
    ///         Only usable if the item is not rented
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function withdraw(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];
        if (rent.owner != msg.sender) revert NotOwner();
        if (rent.startTime != 0) revert RentedItem();

        _withdraw(rent.owner, contract_, tokenId);
    }


    /// ----- RENT LOGIC ----------------------------------------------

    /// @notice Start a new rent for an item in custody of the RentManager
    ///         Gives ownership of the asset to the DelegationManager
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function startRent(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];

        if (rent.owner == address(0)) revert NotRentable();
        if (rent.startTime != 0) revert RentedItem();
        if (rent.rentee != address(0) && rent.rentee != msg.sender) revert OnlyRentableOTC(rent.rentee);
        if (msg.value < rent.weeklyFee || msg.value % rent.weeklyFee != 0) revert WrongPaymentAmount();
        if (msg.value > _maxPayableFee(rent)) revert OverDeadline();
        
        _startRent(contract_, tokenId, rent.owner, msg.sender, msg.value);

        emit RentStart(contract_, tokenId, msg.sender, rent.weeklyFee == 0 ? rent.deadline : msg.value / rent.weeklyFee);
    }

    /// @notice Extend the rent period by paying more fees
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function extendRent(address contract_, uint256 tokenId) external payable {
        RentData memory rent = _getRent[contract_][tokenId];

        if (msg.value % rent.weeklyFee != 0) revert WrongPaymentAmount();
        if (msg.value > _maxPayableFee(rent)) revert OverDeadline();
        
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

        if (rent.weeklyFee > 0 && block.timestamp > rent.startTime + 1 weeks * rent.payedFee / rent.weeklyFee) {
            if (block.timestamp < rent.deadline) {
                _endRent(rent.owner, contract_, tokenId, false);
            } else {
                _endRent(rent.owner, contract_, tokenId, true);
            }

            (bool success, ) = msg.sender.call{value: rent.payedFee * KEEPER_FEE / 100}("");
            require(success);

        } else {
            if (rent.owner != msg.sender) revert NotOwner();

            _endRent(rent.owner, contract_, tokenId, true);

            (uint256 payback, uint256 value) = _paybackHelper(rent);
            if (msg.value != value) revert WrongPaymentAmount();

            (bool success, ) = rent.rentee.call{value: payback}("");
            require(success); 
        }

        emit RentEnd(contract_, tokenId);
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

    /// @notice Start a new rent for an item in custody of the RentManager
    ///         Gives ownership of the asset to the DelegationManager
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    /// @param rentee The address to which the item is rented
    /// @param payedFee The fee payed by the rentee
    function _startRent(address contract_, uint256 tokenId, address owner, address rentee, uint256 payedFee) internal {
        ERC721 nft = ERC721(contract_);

        _getRent[contract_][tokenId].rentee = rentee;
        _getRent[contract_][tokenId].payedFee = payedFee;
        _getRent[contract_][tokenId].startTime = block.timestamp;

        (bool success, ) = owner.call{value: msg.value * (100 - KEEPER_FEE) / 100}("");
        require(success);

        if (address(_getDelegation[contract_]) == address(0)) {
            DelegationManager newDelegation = new DelegationManager(contract_, nft.name(), nft.symbol());
            _getDelegation[contract_] = newDelegation;

            nft.approve(address(newDelegation), tokenId);
            newDelegation.deposit(owner, msg.sender, tokenId);
        } else {        
            DelegationManager delegation = _getDelegation[contract_];

            nft.approve(address(delegation), tokenId);
            delegation.deposit(owner, msg.sender, tokenId);
        }
    }

    /// @notice Reclaim ownership of an item by transfering it away from the DelegationManager
    /// @param owner Original owner of the item
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    /// @param isOver Whether the item is sent back to its owner (true) or not (false)
    function _endRent(address owner, address contract_, uint256 tokenId, bool isOver) internal {
        DelegationManager delegation = _getDelegation[contract_];
        delegation.withdraw(tokenId);
        
        if (isOver) {
            _withdraw(owner, contract_, tokenId);
        } else {
            delete _getRent[contract_][tokenId].rentee;
            delete _getRent[contract_][tokenId].startTime;
            delete _getRent[contract_][tokenId].payedFee;
        }
    }

    
    /// ----- HELPER FUNCTIONS ----------------------------------------

    /// @notice Get the maximum payable fee according to the deadline
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function maxPayableFee(address contract_, uint256 tokenId) public view returns (uint256) {
        RentData memory rent = _getRent[contract_][tokenId];
        return _maxPayableFee(rent);
    }

    /// @notice Internal function to get the maximum payable fee according to the deadline
    /// @param rent Relevant rent data
    function _maxPayableFee(RentData memory rent) internal view returns (uint256) {
        if (rent.startTime == 0) {
            return (rent.weeklyFee / 1 weeks * (rent.deadline - block.timestamp));
        } else {
            return (rent.weeklyFee / 1 weeks * (rent.deadline - rent.startTime)) - rent.payedFee;
        }
    }

    /// @notice Get the required payback to end a rent before closure
    /// @param contract_ ERC721 contract address
    /// @param tokenId The token id for the given item
    function paybackHelper(address contract_, uint256 tokenId) public view returns (uint256, uint256) {
        RentData memory rent = _getRent[contract_][tokenId];
        return _paybackHelper(rent);
    }

    /// @notice Internal function to get the required payback to end a rent before closure
    /// @param rent Relevant rent data
    function _paybackHelper(RentData memory rent) internal view returns (uint256, uint256) {
        uint256 elapsedWeeks = (block.timestamp - rent.startTime) / 1 weeks;
        uint256 payback = rent.payedFee - elapsedWeeks * rent.weeklyFee;

        return (payback, payback - rent.payedFee * KEEPER_FEE / 100);
    }
}