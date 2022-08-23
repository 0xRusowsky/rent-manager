# RentManager
 
RentManager is an implementation of a standalone and trustless contract that safely enables peer-to-peer NFT renting.

Rents are achieved by using the DelegationManager, a contract that holds temporary ownership of the delegated NFT while the rent lasts.
The DelegationManager wraps the rented NFT, maintaining ownership of the underlying, but minting a delegated version of it for the renter. Thanks to this design, renters can proove they have temporary ownership by using an "ownership proxy NFT" of the original NFT.

RentManager is my answer to [Artemis Education web3 bootcamp](https://artemis.education/) call-to-action.
