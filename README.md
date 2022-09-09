# RentManager
 
RentManager is an implementation of a standalone and trustless contract that safely enables peer-to-peer NFT renting.

Rents are achieved by using the DelegationManager, a contract that holds temporary ownership of the delegated NFT while the rent lasts.
The DelegationManager wraps the rented NFT, maintaining ownership of the underlying, but minting a delegated version of it for the renter. Thanks to this design, renters can prove they have temporary ownership by owning a "proxy NFT" backed by the original NFT.

RentManager is my answer to [Artemis Education web3 bootcamp](https://artemis.education/) call-to-action.

# Design

As briefly described above, this implementation works thanks to 2 different contracts, the RentManager and the DelegationManager. The following diagrams describe the high-level mechanisms and functionalities of both contracts.

## DelegationManager

**New Delegation**
![DelegationManager - New Delegation](new-delegation.jpg?raw=true "DelegationManager - New Delegation")
**End Delegation**
![DelegationManager - End Delegation](end-delegation.jpg?raw=true "DelegationManager - End Delegation")

## RentManager

**Deposit**
![RentManager - Deposit](deposit.jpg?raw=true "RentManager - Deposit")
**New Rent**
![RentManager - New Rent](new-rent.jpg?raw=true "RentManager - New Rent")
**Owner Closure**
![RentManager - Owner Closure](owner-closure.jpg?raw=true "RentManager - Owner Closure")
**Keeper Closure**
![RentManager - Keeper Closure](keeper-closure.jpg?raw=true "RentManager - Keeper Closure")