// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

//minting
//buy
//sell
//list
//cancel
//resell
//royality
//custom token
// 1.  ERC 1155/ERC 721 Support
// 2.  Royalties/Commissions  
// 3.  Ability to edit metadata
// 4.  Adjust price of NFTs (metadata and contract based)
// 5. Support of USDC and my custom token . If NFT minting is in my token , buys will be in my token only.
// 6. Ability to support videos, WebP gifs, JPEG, MP4, PNGs
// 7. Ability to support most common wallet providers
// 8. Custom URL
// 9. S3 Bucket Support (or any other)
// 10. Possibility of NFT owners to transfer NFT
contract MyToken is IERC1155, ERC1155, ERC1155Receiver, Ownable {
    IERC20 public customToken;
    IERC1155 public myToken;
    uint256 private tokenId;
    uint256 public minitingFeeToken;
    uint256 public mintingFeeUsdc;
    uint256 royalityInBips;
    enum Status {
        available,
        onSell,
        sold
    }

    struct Royality {
        address owner;
        uint256 id;
        uint256 royalityInbips;
    }
    mapping(address => Royality) public royalties;

    struct Nft {
        address from;
        uint256 id;
        // string Token;
    }
    struct ListNft {
        uint256 id;
        address owner;
        uint256 price;
        Status status;
    }
    mapping(uint256 => ListNft) public _listings;
    mapping(uint256 => Nft) public mintedNft; //mintedNft

    constructor(address _customToken) ERC1155("https://app.pinata.cloud/") {
        customToken = IERC20(_customToken);
        myToken = IERC1155(address(this));
        royalityInBips = 1000; //in bips 1000 is equal to 10%
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function setMintFeeToken(uint256 _fee) public onlyOwner {
        minitingFeeToken = _fee;
    }

    function setFeeUsdc(uint256 _fee) public onlyOwner {
        mintingFeeUsdc = _fee;
    }

    function mint(
        address account,
        // uint256 id,
        bytes memory data
    ) public {
        // tokenId = id;
        require(
            customToken.balanceOf(msg.sender) >= minitingFeeToken,
            "don't have enough balance to mint"
        );
        customToken.transferFrom(msg.sender, address(this), minitingFeeToken);
        mintedNft[tokenId] = Nft(msg.sender, tokenId);
        _mint(account, tokenId, 1, data);
        tokenId++;
    }

    function listNfts(
        uint256 _id,
        uint256 _price,
        bytes memory _data
    ) public {
        require(msg.sender == mintedNft[_id].from);
        _listings[_id] = ListNft(_id, msg.sender, _price, Status(1));
         super.safeTransferFrom(msg.sender, address(this), _id, 1, _data);//now the ownerof an nft is set to previous although nft is transfered to a contract


    }

    function buyNft(uint256 _id, uint256 _price) public {
        require(
            msg.sender != _listings[_id].owner,
            "you can't buy your own nft"
        );
        require(
            _listings[_id].status == Status(1),
            "not available to be bought"
        );
        require(_price >= _listings[_id].price, "price is not enough");
        // Transfer the NFT from the contract (owner) to the buyer
        address reciever = _listings[_id].owner;//the address for recieving rouality/ previous owner
        uint256 royality = calculateRoyalty(_id);//royality amount for a token calculated with the help of it's id
        uint256 nftPrice = _listings[_id].price;
        uint256 toContract = (nftPrice - royality);
        customToken.transferFrom(msg.sender, reciever, royality);
        customToken.transferFrom(msg.sender, address(this), toContract);
        myToken.safeTransferFrom(address(this), msg.sender, _id, 1, "");
        mintedNft[_id] = Nft(msg.sender, _id);
        _listings[_id].status = Status(2);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function editPrice(uint256 id, uint256 _newPrice) public {
        require(
            msg.sender == mintedNft[id].from,
            "you are not the owner of id_"
        );
        require(_listings[id].status == Status(0), "not available for sell");
        _listings[id].price = _newPrice;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, ERC1155Receiver, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) public pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    
    function calculateRoyalty(uint256 _id) public view returns (uint256) {
        // Calculate the royalty amount as a percentage of the NFT price
        uint256 myAmount = _listings[_id].price;
        uint256 royaltyAmount = (myAmount * royalityInBips) / 10000;
        return royaltyAmount;
    }

    function cancelListing(uint256 _id) public {
        require(
            msg.sender == mintedNft[_id].from,
            "Only the owner can cancel the listing"
        );
        require(
            _listings[_id].status == Status(1) || _listings[_id].status == Status(2) ,
            "NFT is not available for cancellation"
        );
        myToken.safeTransferFrom(address(this), msg.sender, _id, 1, "");

        delete _listings[_id];
    }

    function resellNft(uint256 _id, uint256 _newPrice) public {
        require(
            msg.sender == mintedNft[_id].from,
            "Only the owner can resell the NFT"
        );
        require(
            _listings[_id].status == Status(2),
            "NFT must be sold to be resold"
        );

        super.safeTransferFrom(msg.sender, address(this), _id, 1, "");

        _listings[_id] = ListNft(_id, msg.sender, _newPrice, Status.available);
    }

    function getNftStatus(uint256 _id)public  view returns(Status){
        return _listings[_id].status;
    }

    function getNftPrice(uint256 _id)public view returns(uint256){
        require(_listings[_id].status == Status(1) || _listings[_id].status == Status(2),"nft is not on sell");
         return _listings[_id].price;
    }
}