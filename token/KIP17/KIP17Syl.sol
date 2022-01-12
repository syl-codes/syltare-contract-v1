pragma solidity ^0.5.0;

import "./KIP17.sol";
import "./KIP17Metadata.sol";
import "./KIP17Enumerable.sol";
import "../../access/roles/MinterRole.sol";
import "../../math/SafeMath.sol";
import "../../utils/String.sol";

contract KIP17Syl is KIP17, KIP17Enumerable, KIP17Metadata, MinterRole{
    // If someone burns NFT in the middle of minting,
    // the tokenId will go wrong, so use the index instead of totalSupply().
    uint256 private _mintIndexForSale;
    uint256 private _mintIndexForDutch;

    address private _metakongzContract;

    //Shared
    uint256 private _mintLimit;         // Maximum purchase per person.
    string  private _tokenBaseURI;

    //Separated. Normal Sale
    uint256 private _mintStartBlockForSale; // In blockchain, blocknumber is the standard of time.
    uint256 private _maxAmountForSale;      // Maximum purchase volume of normal sale.
    uint256 private _mintPriceForSale;      // Could be 200 or 300

    //Separated. Dutch Auction
    uint256 private _mintStartBlockForDutch;      // In blockchain, blocknumber is the standard of time.
    uint256 private _maxAmountForDutch;           // Maximum purchase volume of dutch auction.
    uint256 private _intervalBlockCount;          // The number of blocks until the next Dutch point. 300.
    uint256 private _startAuctionPrice;           // Could be 600
    uint256 private _lowestAuctionPrice;          // Could be 400
    uint256 private _discountRatePerDutch;        // Could be 50
    uint256 private _risingVolumePerPurchase;     // Could be 1
    uint256 private _participantCount;
    uint256 private _maxParticipantCountPerDutch; // Could be 20. A little below half of _discountRatePerDutch.

    constructor () public {
      _mintIndexForSale = 0;
      _mintIndexForDutch = 0;
      _participantCount = 0;
      _tokenBaseURI = "https://metadata.syltare.com/mint/";
    }

    function withdraw() external onlyMinter{
      msg.sender.transfer(address(this).balance);
    }

    function mintingInformation() external view returns (uint256[15] memory){
      uint256[15] memory info =
        [_mintLimit, _mintStartBlockForSale, _mintStartBlockForDutch, _maxAmountForSale,
          _mintPriceForSale, _maxAmountForDutch, _intervalBlockCount, _startAuctionPrice,
          _lowestAuctionPrice, _discountRatePerDutch, _risingVolumePerPurchase, _participantCount,
          _maxParticipantCountPerDutch, _mintIndexForSale, _mintIndexForDutch];
      return info;
    }

    function dutchSyl(uint256 requestedCount) external payable {
      require(block.number >= _mintStartBlockForDutch, "Not started ");
      require(requestedCount > 0 && requestedCount <= _mintLimit, "Not allowed mint count");

      uint256 dutchPrice = currentPrice();
      require(msg.value >= dutchPrice.mul(requestedCount), "Not enough Klay");

      require(_mintIndexForDutch.add(requestedCount) <= _maxAmountForDutch, "Exceed max amount");

      for(uint256 i = 0; i < requestedCount; i++) {
        uint256 _totalMintIndexForDutch = _mintIndexForDutch + _maxAmountForSale;
        _mint(msg.sender, _totalMintIndexForDutch);
        _setTokenURI(_totalMintIndexForDutch,
                     string(abi.encodePacked(_tokenBaseURI, String.uint2str(_totalMintIndexForDutch), ".json")));
        _mintIndexForDutch = _mintIndexForDutch.add(1);
      }
      if(dutchPrice < _startAuctionPrice){    // GO! His Auction!
        uint256 jumpCount = _jumpCount();
        uint256 maxParticipantCount = jumpCount.mul(_maxParticipantCountPerDutch);
        if(_participantCount < maxParticipantCount){
          _participantCount = _participantCount.add(1);
        }
      }
    }
    
    function mintSyl(uint256 requestedCount) external payable {
      require(block.number >= _mintStartBlockForSale, "Not started ");
      require(requestedCount > 0 && requestedCount <= _mintLimit, "Not allowed mint count");
      require(msg.value >= _mintPriceForSale.mul(requestedCount), "Not enough Klay");

      require(_mintIndexForSale.add(requestedCount) <= _maxAmountForSale, "Exceed max amount");

      bool success;
      bytes memory data;
      (success, data) = _metakongzContract.call(abi.encodeWithSignature("balanceOf(address)", msg.sender));
      if(!success){
        revert();
      }
      uint256 balanceOfSender = abi.decode(data, (uint256));
      require(balanceOfSender > 0, "Sender should have at least one metakongz");

      for(uint256 i = 0; i < requestedCount; i++) {
        _mint(msg.sender, _mintIndexForSale);
        _setTokenURI(_mintIndexForSale,
                     string(abi.encodePacked(_tokenBaseURI, String.uint2str(_mintIndexForSale), ".json")));
        _mintIndexForSale = _mintIndexForSale.add(1);
      }
    }

    function setupSale(address newMetakongzContract,
                       uint256 newMintLimit,
                       uint256 newMintStartBlockForSale,
                       uint256 newMaxAmountForSale,
                       uint256 newMintPriceForSale) external onlyMinter{
      _metakongzContract = newMetakongzContract;
      _mintLimit = newMintLimit;
      _mintStartBlockForSale = newMintStartBlockForSale;
      _maxAmountForSale = newMaxAmountForSale;
      _mintPriceForSale = newMintPriceForSale;
    }

    function setupDutchAuction( uint256 newMintLimit,
                                uint256 newMintStartBlockForDutch,
                                uint256 newMaxAmountForDutch,
                                uint256 newIntervalBlockCount,
                                uint256 newStartAuctionPrice,
                                uint256 newLowestAuctionPrice,
                                uint256 newDiscountRatePerDutch,
                                uint256 newRisingVolumePerPurchase,
                                uint256 newMaxParticipantCountPerDutch) external onlyMinter{
      _mintLimit = newMintLimit;
      _mintStartBlockForDutch = newMintStartBlockForDutch;
      _maxAmountForDutch = newMaxAmountForDutch;

      _intervalBlockCount = newIntervalBlockCount;
      _startAuctionPrice = newStartAuctionPrice;
      _lowestAuctionPrice = newLowestAuctionPrice;
      _discountRatePerDutch = newDiscountRatePerDutch;
      _risingVolumePerPurchase = newRisingVolumePerPurchase;
      _maxParticipantCountPerDutch = newMaxParticipantCountPerDutch;
    }

    function currentPrice() public view returns (uint256){
      uint256 calculatedPrice;
      uint256 jumpCount = _jumpCount();
      uint256 totalDiscount = jumpCount.mul(_discountRatePerDutch);
      uint256 totalRisingVolume = _participantCount.mul(_risingVolumePerPurchase);
      uint256 risedPrice = _startAuctionPrice.add(totalRisingVolume);
      if(risedPrice > totalDiscount){
        calculatedPrice = risedPrice.sub(totalDiscount);
      }else{
        calculatedPrice = 0;
      }

      if(calculatedPrice > _startAuctionPrice){
        calculatedPrice = _startAuctionPrice;
      }else if(calculatedPrice < _lowestAuctionPrice){
        calculatedPrice = _lowestAuctionPrice;
      }
      return calculatedPrice;
    }

    function _jumpCount() private view returns (uint256){
      uint256 currentBlocknumber = block.number;
      uint256 _elapsedBlocks = currentBlocknumber.sub(_mintStartBlockForDutch);
      require (_elapsedBlocks >= 0, "Math error");

      uint256 jumpCount = _elapsedBlocks.div(_intervalBlockCount);
      return jumpCount;
    }
}
