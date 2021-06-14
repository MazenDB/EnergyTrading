pragma solidity =0.6.0;

contract Registration {
    
    struct actortype{
        bool exists;
        uint deposit;
    }

    address private owner;
    mapping(address=>actortype) public EV;
    mapping(address=>actortype) public EP;

    event ElectricVehicleRegistered(address EV);
    event EnergyProviderRegistered(address EP);

    
    modifier EVorEP {
        require(EV[msg.sender].exists && EP[msg.sender].exists,
        "Sender not authorized."
        );
        _;
    }     
    
    
    constructor() public{
        owner=msg.sender;
    }
    
    function registerEV() public{
        require(!EV[msg.sender].exists && !EP[msg.sender].exists,
        "Address already used");
        
        EV[msg.sender].exists=true;
        emit ElectricVehicleRegistered(msg.sender);
    }
    
    function registerEP() public{
        require(!EV[msg.sender].exists && !EP[msg.sender].exists,
        "Address already used");
        
        EP[msg.sender].exists=true;
        emit EnergyProviderRegistered(msg.sender);
    }
    
    function EVExists(address EVaddress) view public returns (bool) {
        return EV[EVaddress].exists;
    }
    
    function EPExists(address EPaddress) view public returns (bool) {
        return EP[EPaddress].exists;
    }
    
    function isOwner(address o) view public returns (bool){
        return(o==owner);
    }
    
    function depositAmount(uint amount)public EVorEP{
        if(EV[msg.sender].exists){
            EV[msg.sender].deposit+=amount;
        }
        else if(EP[msg.sender].exists){
            EP[msg.sender].deposit+=amount;
        }
    }

    function getDeposit(address actor)public EVorEP view returns(uint){
        if(EV[actor].exists){
            return EV[actor].deposit;
        }
        else if(EP[msg.sender].exists){
            return EP[msg.sender].deposit;
        }
    }


    
    function deductDeposit(uint amount, address EVAddress)public EVorEP{
        if(EV[EVAddress].exists){
            EV[EVAddress].deposit-=amount;
        }
        else if(EP[EVAddress].exists){
            EP[EVAddress].deposit-=amount;
        }
    }



}


contract EnergyTrading{
    
    struct order{
        uint kWh;
        address EV;
        uint timestamp;
        uint bid;
        bool auctionOpen;
        address payable lastBidder;
        uint minRep;

    }
    
    Registration registrationContract;
    Reputation reputationContract;
    mapping(uint=>order) orderRequest;
    address owner;
    uint orderNumber;
    
    
    event DepositConfirmed(address EVAddress,uint amount);
    event AuctionStarted(uint requestNumber,uint maximumBid, uint requestedkWh, uint minReputation);
    event newBid(uint requestNumber,uint bidAmount, address bidderAddress);
    event AuctionEnded(uint requestNumber, address bidderAddress, uint lowestBid);
    event ChargingProcessEnded(address EPaddress, address EVAddress);


    
    
    modifier onlyOwner{
        require(msg.sender==owner,
        "Sender not authorized."
        );
        _;
    }  
    
    
    modifier onlyEV {
        require(registrationContract.EVExists(msg.sender),
        "Sender not authorized."
        );
        _;
    }      
    
    modifier onlyEP {
        require(registrationContract.EPExists(msg.sender),
        "Sender not authorized."
        );
        _;
    }      
    
    
    constructor(address registrationAddress, address reputationAddress)public {
        registrationContract=Registration(registrationAddress);
        reputationContract=Reputation(reputationAddress);
        
        require (registrationContract.isOwner(msg.sender),
        "Sender not authorized.");

        require (reputationContract.isOwner(msg.sender),
        "Sender not authorized.");
        
        
        orderNumber=uint(keccak256(abi.encodePacked(msg.sender,now,address(this))));
        owner=msg.sender;
    }
    
    function newRequest(uint requestedkWh, uint maxPrice, uint minReputation)payable public onlyEV{
        
        require(msg.value==maxPrice,
        "Deposit by EV is insufficient."
        );
        
        emit DepositConfirmed(msg.sender,maxPrice);
        
        orderRequest[orderNumber].kWh=requestedkWh;
        orderRequest[orderNumber].EV=msg.sender;
        orderRequest[orderNumber].timestamp=now;
        orderRequest[orderNumber].bid=maxPrice;
        orderRequest[orderNumber].auctionOpen=true;
        orderRequest[orderNumber].minRep=minReputation;
        
        emit AuctionStarted(orderNumber,maxPrice,requestedkWh,minReputation);

                
        orderNumber++;
        
        registrationContract.depositAmount(maxPrice);
        
    }
    
    function makeBid(uint requestNumber, uint bidAmount) onlyEP public payable{
        
        require(msg.value==bidAmount,
        "Deposit by EP is insufficient."
        );    

        require(bidAmount<orderRequest[requestNumber].bid && bidAmount>0,
        "A lower bid has been previously placed."
        );    
        
        require(reputationContract.getRep(msg.sender)>=orderRequest[requestNumber].minRep,
        "EP reputation is insufficient to make a bid."
        );    
        
        require(orderRequest[requestNumber].auctionOpen,
        "The request has been closed by the EV"
        );
        
        if(orderRequest[requestNumber].lastBidder!=address(0)){
            registrationContract.deductDeposit(orderRequest[requestNumber].bid,orderRequest[requestNumber].lastBidder);
            orderRequest[requestNumber].lastBidder.transfer(orderRequest[requestNumber].bid);
        }
        
        
        registrationContract.depositAmount(bidAmount);
        orderRequest[requestNumber].lastBidder=msg.sender;
        orderRequest[requestNumber].bid=bidAmount;
        
        emit newBid(requestNumber, bidAmount, msg.sender);

        
    }
    
    function acceptLowestBid(uint requestNumber) onlyEV public{
        require(orderRequest[requestNumber].auctionOpen,
        "The request has been closed by the EV"
        );
        
        require(orderRequest[requestNumber].EV==msg.sender,
        "The request does not belong to this EV address"
        );
        
        
        orderRequest[requestNumber].auctionOpen=false;
        if(orderRequest[requestNumber].lastBidder!=address(0)){
            orderRequest[requestNumber].lastBidder.transfer(orderRequest[requestNumber].bid);
            registrationContract.deductDeposit(orderRequest[requestNumber].bid,msg.sender);

        }
        emit AuctionEnded(requestNumber, orderRequest[requestNumber].lastBidder, orderRequest[requestNumber].bid);

    }
    
    function endCharging(uint requestNumber) onlyEP public{
        require(orderRequest[requestNumber].lastBidder!=address(0));
        
        require(!orderRequest[requestNumber].auctionOpen,
        "Auction still open for bidding"
        );
        
        address payable tempBidder=orderRequest[requestNumber].lastBidder;
        
        msg.sender.transfer(registrationContract.getDeposit(msg.sender));
        registrationContract.deductDeposit(registrationContract.getDeposit(msg.sender), msg.sender);
        
        tempBidder.transfer(registrationContract.getDeposit(tempBidder));
        registrationContract.deductDeposit(registrationContract.getDeposit(msg.sender),tempBidder);
        
        emit ChargingProcessEnded(msg.sender, tempBidder);
        
    }
}


contract Reputation{
    

    Registration registrationContract;
    mapping(address=>uint) EPRep;
    address owner;
    uint constant adjusting_factor = 4;

    event FeedbackRecorded(address EP, uint newRep);
    
    
    modifier onlyOwner{
        require(msg.sender==owner,
        "Sender not authorized."
        );
        _;
    }  
    
    modifier onlyEV{
        require(registrationContract.EVExists(msg.sender),
        "Sender not authorized."
        );
        _;
    }  
    
    struct feedbackType{
        mapping(address=>bool) EP;
        mapping(address=>bool) feedbackQuality;
    }
    
    mapping(address=>feedbackType) feedbackEP;


    constructor(address registrationAddress)public {
        registrationContract=Registration(registrationAddress);
        
        owner=msg.sender;
    }
    
    function isOwner(address o) view public returns (bool){
        return(o==owner);
    }
    
    function getRep(address EPAddress) public view returns(uint){
        return EPRep[EPAddress];
    }
    
    function newEP(address EP) public onlyOwner{
        require(EPRep[EP]==0,
        "Energy PRovider already added");
        require(registrationContract.EPExists(EP),
        "Provided EP address is wrong"
        );
        EPRep[EP]=80;
    }
    
    function provideFeedback (address EPAddress, bool feedback) public onlyEV {
        require(!feedbackEP[msg.sender].EP[EPAddress],
        "Retailer has already provided feedback for this supplier"
        );

        feedbackEP[msg.sender].EP[EPAddress]=true;
        feedbackEP[msg.sender].feedbackQuality[EPAddress]=feedback;
        //calculateRep(supplier);
    }
    
    function calculateRep (address EPAddress) public {
        
        uint cr;

        if(feedbackEP[msg.sender].feedbackQuality[EPAddress]){
            cr = (EPRep[EPAddress]*95)/(4*adjusting_factor);
            cr /= 100;
            EPRep[EPAddress]+=cr;
        }
        else{

            cr = (EPRep[EPAddress]*95)/(4*(10-adjusting_factor));
            cr /= 100;
            EPRep[EPAddress]-=cr;
        }
        if (EPRep[EPAddress]<0){
            EPRep[EPAddress]=0;
        }
        else if (EPRep[EPAddress]>100){
            EPRep[EPAddress]=100;
        }
        
        emit FeedbackRecorded(EPAddress, EPRep[EPAddress]);

  }
    

}
