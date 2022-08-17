// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "solmate/tokens/ERC721.sol";

contract WrappedERC721 is ERC721{
    ERC721 public immutable collection;
    address private _owner;

    modifier onlyOwner() virtual {
        require(msg.sender == _owner, "NOT_OWNER");
        _;
    }

    constructor(address _collection, string memory _name, string memory _symbol)
        ERC721(
            string(abi.encodePacked("wrapped", _name)),
            string(abi.encodePacked("w",_symbol))
        ) {
        collection = ERC721(_collection);
        _owner = msg.sender;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return collection.tokenURI(id);
    }

    function wrap(address to, uint256 id) external {
        collection.transferFrom(msg.sender, address(this), id);
        _mint(to, id);
    }

    function unwrap(uint256 id) external onlyOwner {
        _burn(id);
        collection.transferFrom(address(this), msg.sender, id);
    }
}