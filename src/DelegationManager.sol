// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "solmate/tokens/ERC721.sol";

/// @notice Implementation of an NFT delegation contract
/// @author 0xruswowsky (https://github.com/0xRusowsky/rent-manager/blob/main/src/DelegationManager.sol)
contract DelegationManager is ERC721{

    /// ----- EVENTS --------------------------------------------------

    event NewDelegation(address indexed owner, address indexed delegatee, uint256 tokenId);
    event EndDelegation(address indexed delegatee, uint256 tokenId);

    /// ----- DELEGATION STORAGE --------------------------------------

    /// @notice Underlying ERC721
    ERC721 public immutable realERC721;

    /// @notice Relevant delegation data
    struct DelegationData {
        address realOwner;
        address accessControl;
    }

    /// @notice Mapping between tokenId and its DelegationData
    mapping(uint256 => DelegationData) _dataOf;

    /// ----- CONSTRUCTOR ---------------------------------------------

    /// @param _contract Contract of the underlying ERC721
    /// @param _name Name of the underlying ERC721
    /// @param _symbol Symbol of the underlying ERC721
    constructor(address _contract, string memory _name, string memory _symbol)
        ERC721(
            string(abi.encodePacked("wrapped ", _name)),
            string(abi.encodePacked("w",_symbol))
        ) {
        realERC721 = ERC721(_contract);
    }

    /// ----- METADATA AND STORAGE LOGIC ------------------------------

    /// @notice Return the item URI
    /// @param tokenId Token id for the given item
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return realERC721.tokenURI(tokenId);
    }

    /// @notice Return the real owner of the underlying ERC721
    /// @param tokenId Token id for the given item
    function realOwnerOf(uint256 tokenId) public view returns (address) {
        return _dataOf[tokenId].realOwner;
    }

    /// ----- DELEGATION LOGIC ----------------------------------------

    /// @notice Delegate an item by giving ownership to the DelegationManager
    /// @param realOwner Owner of the underlying item
    /// @param delegatee Address that will have ownership of the wrapped version of the item
    /// @param tokenId Token id for the given item
    function deposit(address realOwner, address delegatee, uint256 tokenId) external {
        _dataOf[tokenId] = DelegationData(realOwner, msg.sender);

        realERC721.transferFrom(msg.sender, address(this), tokenId);
        _mint(delegatee, tokenId);

        emit NewDelegation(realOwner, delegatee, tokenId);
    }

    /// @notice Unwrap the underlying ERC721 and give ownership back to its owner
    /// @param tokenId Token id for the given item
    function withdraw(uint256 tokenId) external {
        require(msg.sender == _dataOf[tokenId].accessControl, "UNAUTHORIZED");

        address delegatee = _ownerOf[tokenId];
        delete _dataOf[tokenId];
        
        _burn(tokenId);
        realERC721.transferFrom(address(this), msg.sender, tokenId);

        emit EndDelegation(delegatee, tokenId);
    }
}