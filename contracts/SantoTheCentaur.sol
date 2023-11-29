// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SantoTheCentaur is ERC721, ERC2981, ERC721Enumerable, Pausable, Ownable, AccessControl, ReentrancyGuard {
    using Strings for uint256;
    using Counters for Counters.Counter;

    AggregatorV3Interface internal dataFeed;

    enum Status {
        WhiteListSale,
        PublicSale,
        FreeSale
    }

    string private baseURI;
    string private baseExtension;
    string private mysteryURI;
    uint256 public mysteryStartId;
    
    uint8 public groupCurrent;
    uint256 public openSupply;
    mapping(Status => uint256) public saleStartTime;
    mapping(Status => uint256) public keepTime;
    mapping(Status => uint256) public salePrice;
    mapping(Status => uint256) public mintMax;
    mapping(Status => uint256) public mintPerMax;
    mapping(Status => uint256) public mintCount;

    mapping(address => mapping(uint8 => uint256)) public amountMintedPerWhiteList;
    mapping(address => mapping(uint8 => uint256)) public amountMintedPerPublic;
    mapping(address => mapping(uint8 => uint256)) public amountMintedPerFree;

    mapping(uint8 => uint256) public whiteListGroupCount;
    mapping(address => mapping(uint8 => bool)) private whiteList;

    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");
    Counters.Counter private _tokenIdCounter;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _saleStartTime,
        address _serverRole,
        string memory _mysteryURI
    ) ERC721(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SERVER_ROLE, _serverRole);

        dataFeed = AggregatorV3Interface(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        );

        openSupply = 7777;
        mintMax[Status.WhiteListSale] = 3500;
        mintMax[Status.PublicSale] = 1500;
        mintMax[Status.FreeSale] = 200;

        mintPerMax[Status.WhiteListSale] = 2;
        mintPerMax[Status.PublicSale] = 2;
        mintPerMax[Status.FreeSale] = 1;

        salePrice[Status.WhiteListSale] = 30000000 gwei;
        salePrice[Status.PublicSale] = 50000000 gwei;
        salePrice[Status.FreeSale] = 30000000 gwei;

        
        keepTime[Status.WhiteListSale] = 3 days;
        keepTime[Status.PublicSale] = 2 days;
        keepTime[Status.FreeSale] = 1 days;

        saleStartTime[Status.WhiteListSale] = _saleStartTime;
        saleStartTime[Status.PublicSale] = _saleStartTime + 1 days;
        saleStartTime[Status.FreeSale] = _saleStartTime + 2 days;

        mysteryURI = _mysteryURI;
        setGroupCurrent(1);
        _setDefaultRoyalty(msg.sender, 500);
    }

    modifier _notContract() {
        uint256 size;
        address addr = msg.sender;
        assembly {
            size := extcodesize(addr)
        }
        require(size == 0, "Contract is not allowed");
        require(msg.sender == tx.origin, "Proxy contract is not allowed");
        _;
    }

    modifier _saleBetweenPeriod(uint256 _startTime, uint256 _endTime) {
        require(currentTime() >= _startTime, "Sale has not started yet");
        require(currentTime() < _endTime, "Sale is finished");
        _;
    }

    function whitelistMint(uint256 amount)
        external
        payable
        whenNotPaused
        _notContract
        _saleBetweenPeriod(saleStartTime[Status.WhiteListSale], saleStartTime[Status.WhiteListSale] + keepTime[Status.WhiteListSale])
        nonReentrant
    {
        Status _current = Status.WhiteListSale;
        uint8 _group = groupCurrent;

        require(whiteList[msg.sender][_group], "Not in whitelist");
        require(amountMintedPerWhiteList[msg.sender][_group] + amount <= mintPerMax[_current], "Minted reached the limit");
        require(mintCount[_current] + amount <= mintMax[_current], "Exceeded max mint");
        require(msg.value >= salePrice[_current] * amount, "Not enough funds");

        mintCount[_current] += amount;
        amountMintedPerWhiteList[msg.sender][_group] += amount;
        _batchMint(msg.sender, amount);
    }

    function publicSaleMint(uint256 amount)
        external
        payable
        whenNotPaused
        _notContract
        _saleBetweenPeriod(saleStartTime[Status.PublicSale], saleStartTime[Status.PublicSale] + keepTime[Status.PublicSale])
        nonReentrant
    {
        Status _current = Status.PublicSale;
        uint8 _group = groupCurrent;

        require(amountMintedPerPublic[msg.sender][_group] + amount <= mintPerMax[_current], "Minted reached the limit");
        require(mintCount[_current] + amount <= mintMax[_current], "Exceeded max mint");

        uint256 totalValue = salePrice[_current] * amount;
        require(msg.value >= totalValue, "Not enough funds");

        mintCount[_current] += amount;
        amountMintedPerPublic[msg.sender][_group] += amount;
        _batchMint(msg.sender, amount);
    }

    function freeMint()
        external
        payable
        whenNotPaused
        _notContract
        _saleBetweenPeriod(saleStartTime[Status.FreeSale], saleStartTime[Status.FreeSale] + keepTime[Status.FreeSale])
        nonReentrant
    {
        Status _current = Status.FreeSale;
        uint8 _group = groupCurrent;
        uint256 amount = 1;

        require(
            amountMintedPerWhiteList[msg.sender][_group] > 0 || amountMintedPerPublic[msg.sender][_group] > 0,
            "No permission"
        );
        require(amountMintedPerFree[msg.sender][_group] + amount <= mintPerMax[_current], "Minted reached the limit");
        require(mintCount[_current] + amount <= mintMax[_current], "Exceeded max mint");
        require(msg.value >= salePrice[_current] * amount, "Not enough funds");

        mintCount[_current] += amount;
        amountMintedPerFree[msg.sender][_group] += amount;
        _batchMint(msg.sender, amount);
    }

    function _batchMint(address _account, uint256 _quantity) internal {
        require(totalSupply() + _quantity <= openSupply, "Exceeded the open supply limit");

        for (uint256 i = 0; i < _quantity; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_account, tokenId);
        }
    }

    function foundationClaim(address to, uint256 amount) external onlyOwner {
        _batchMint(to, amount);
    }

    function rewardClaim(address[] memory addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            _batchMint(addrs[i], 1);
        }
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        if (tokenId >= mysteryStartId) {
            return string(abi.encodePacked(mysteryURI, tokenId.toString(), ".json"));
        }
        string memory base = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(base, tokenId.toString(), baseExtension)) : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // Whitelist
    function isWhiteList(address addr, uint8 group) public view returns (bool) {
        return whiteList[addr][group];
    }

    function addWhiteList(address addr, uint8 group) public onlyRole(SERVER_ROLE) {
        whiteListGroupCount[group]++;
        whiteList[addr][group] = true;
    }

    function addWhiteListBatch(address[] memory addrs, uint8 group) public onlyRole(SERVER_ROLE) {
        for (uint i = 0; i < addrs.length; i++) {
            addWhiteList(addrs[i], group);
        }
    }

    // Royalty
    function setDefaultRoyalty(address _receiver, uint96 _freeNumerator) public onlyOwner {
        _setDefaultRoyalty(_receiver, _freeNumerator);
    }

    function deleteDefaultRoyalty() public onlyOwner {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _freeNumerator
    ) public onlyOwner {
        _setTokenRoyalty(_tokenId, _receiver, _freeNumerator);
    }

    function resetTokenRoyalty(uint256 _tokenId) public onlyOwner {
        _resetTokenRoyalty(_tokenId);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    // Setting
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setBaseURI(string memory _uri) public onlyOwner {
        baseURI = _uri;
    }

    function setOpenSupply(uint256 _openSupply) public onlyOwner {
        openSupply = _openSupply;
    }

    function setGroupCurrent(uint8 _group) public onlyOwner {
        groupCurrent = _group;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function setSaleStartTime(Status _saleStartTimeStatus, uint256 _saleStartTime) public onlyOwner {
        saleStartTime[_saleStartTimeStatus] = _saleStartTime;
    }

    function setKeepTime(Status _keepTimeStatus, uint256 _keepTime) public onlyOwner {
        keepTime[_keepTimeStatus] = _keepTime;
    }

    function setSalePrice(Status _salePriceStatus, uint256 _salePrice) public onlyOwner {
        salePrice[_salePriceStatus] = _salePrice;
    }

    function setMintPerMax(Status _mintPerMaxStatus, uint256 _max) public onlyOwner {
        mintPerMax[_mintPerMaxStatus] = _max;
    }

    function setMintMax(Status _mintMaxStatus, uint256 _max) public onlyOwner {
        mintMax[_mintMaxStatus] = _max;
    }

    function setMysteryURI(string memory _mysteryURI) public onlyOwner {
        mysteryURI = _mysteryURI;
    }

    function setMysteryStartId(uint256 _mysteryStartId) public onlyOwner {
        mysteryStartId = _mysteryStartId;
    }

    // Tools
    function currentTime() private view returns (uint256) {
        return block.timestamp;
    }

    function withdraw() public onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function getBalanceIds(address _address) public view returns (uint256[] memory) {
        uint256 balance = balanceOf(_address);
        uint256[] memory ids = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 _tokenId = tokenOfOwnerByIndex(_address, i);
            ids[i] = _tokenId;
        }
        return ids;
    }

    function getChainlinkEthDataFeed() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // The following functions are overrides required by Solidity.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}