// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "solmate/tokens/ERC721.sol";

contract DelegationManager is ERC721{

    event NewDelegation(address indexed owner, address indexed delegatee, uint256 tokenId);
    event EndDelegation(address indexed delegatee, uint256 tokenId);

    struct DelegationData {
        address realOwner;
        address accessControl;
    }

    mapping(uint256 => DelegationData) _dataOf;

    ERC721 public immutable realERC721;

    modifier accessControl(uint256 tokenId) virtual {
        require(msg.sender == _dataOf[tokenId].accessControl, "UNAUTHORIZED");
        _; 
    }

    constructor(address _contract, string memory _name, string memory _symbol)
        ERC721(
            string(abi.encodePacked("wrapped ", _name)),
            string(abi.encodePacked("w",_symbol))
        ) {
        realERC721 = ERC721(_contract);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return realERC721.tokenURI(tokenId);
    }

    function realOwnerOf(uint256 tokenId) public view returns (address) {
        return _dataOf[tokenId].realOwner;
    }

    function deposit(address realOwner, address delegatee, uint256 tokenId) external {
        _dataOf[tokenId] = DelegationData(realOwner, msg.sender);

        realERC721.transferFrom(msg.sender, address(this), tokenId);
        _mint(delegatee, tokenId);

        emit NewDelegation(realOwner, delegatee, tokenId);
    }

    function withdraw(uint256 tokenId) external accessControl(tokenId) {
        address delegatee = _ownerOf[tokenId];
        delete _dataOf[tokenId];
        
        _burn(tokenId);
        realERC721.transferFrom(address(this), msg.sender, tokenId);

        emit EndDelegation(delegatee, tokenId);
    }
}