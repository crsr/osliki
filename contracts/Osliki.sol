pragma solidity ^0.4.21;

import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
import '../node_modules/zeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import '../node_modules/zeppelin-solidity/contracts/token/ERC20/SafeERC20.sol';

/*@ToDo:
check check the sequence of event calls
rational
*/
contract Osliki {
  using SafeMath for uint;
  using SafeERC20 for ERC20;

  ERC20 public oslikToken;
  address public oslikiFoundation;
  uint public constant OSLIKI_FEE = 1; // Only for ETH
  uint public fees = 0; // To know how much can be withdrawn in favor of the Foundation

  Order[] public orders;
  Offer[] public offers;
  Invoice[] public invoices;

  enum EnumOrderStatus { New, Process, Fulfilled }
  enum EnumInvoiceStatus { New, Prepaid, Deposit, Paid }
  enum EnumCurrency { ETH, OSLIK }

  event EventNewOrder(uint orderId);
  event EventNewOffer(uint offerId, uint orderId);
  event EventNewInvoice(uint invoiceId, uint orderId);
  event EventPayment(uint invoiceId);

  event EventLog(uint fist, uint sec, uint thrd);

  function Osliki(ERC20 _oslikToken, address _oslikiFoundation) public {
    //require(address(_oslikToken) != 0x0 && _oslikiFoundation != 0x0);

    oslikToken = _oslikToken;
    oslikiFoundation = _oslikiFoundation;

    // plug for invoices[0] cos default invoiceId in all orders == 0
    invoices.push(Invoice({
      sender: 0x0,
      orderId: 0,
      prepayment: 0,
      deposit: 0,
      currency: EnumCurrency.ETH,
      depositHash: 0x0,
      status: EnumInvoiceStatus.New,
      createdAt: block.number,
      updatedAt: block.number
    }));
  }

  struct Order {
    address customer;
    string from;
    string to;
    string params;
    uint date;
    string message;

    uint[] offerIds;

    address carrier;
    uint invoiceId;

    EnumOrderStatus status;
    uint createdAt;
    uint updatedAt;
  }

  struct Offer {
    address carrier;
    uint orderId;
    string message;
  }

  struct Invoice {
    address sender;
    uint orderId;
    uint prepayment;
    uint deposit;
    EnumCurrency currency;
    bytes32 depositHash;
    EnumInvoiceStatus status;
    uint createdAt;
    uint updatedAt;
  }

  function getFee(uint value) public pure returns (uint) {
    return value.div(100).mul(OSLIKI_FEE);
  }

  function addOrder(
      string from, // geo coord 'lat,lon' or Ethereum address '0x...'
      string to,
      string params,  // format 'weight(kg),length(m),width(m),height(m)'
      uint date,
      string message
  ) public {
    orders.push(Order({
      customer: msg.sender,
      from: from,
      to: to,
      params: params,
      date: date,
      message: message,

      offerIds: new uint[](0),

      carrier: 0x0,
      invoiceId: 0,

      status: EnumOrderStatus.New,
      createdAt: block.number,
      updatedAt: block.number
    }));

    uint orderId = orders.length -1;

    emit EventNewOrder(orderId);
  }

  function addOffer(
      uint orderId,
      string message
  ) public {
    offers.push(Offer({
      carrier: msg.sender,
      orderId: orderId,
      message: message
    }));

    uint offerId = offers.length - 1;

    orders[orderId].offerIds.push(offerId);
    orders[orderId].updatedAt = block.number;

    emit EventNewOffer(offerId, orderId);
  }

  /* @ToDo: check possible issues with invoices[0] */
  function addInvoice(
    uint orderId,
    uint prepayment,
    uint deposit,
    EnumCurrency currency
  ) public {
    invoices.push(Invoice({
      sender: msg.sender,
      orderId: orderId,
      prepayment: prepayment,
      deposit: deposit,
      currency: currency,
      depositHash: '',
      status: EnumInvoiceStatus.New,
      createdAt: block.number,
      updatedAt: block.number
    }));

    uint invoiceId = invoices.length - 1;

    emit EventNewInvoice(invoiceId, orderId);
  }

  function pay(
    uint invoiceId,
    bytes32 depositHash
  ) public payable {
    Invoice storage invoice = invoices[invoiceId];
    Order storage order = orders[invoice.orderId];

    uint prepayment = invoice.prepayment;
    uint deposit = invoice.deposit;
    uint amount = prepayment.add(deposit);

    require(//amount != 0 &&
      order.customer == msg.sender && // can't pay for someone else's orders
      order.status == EnumOrderStatus.New && // can't pay already processed orders
      invoice.status == EnumInvoiceStatus.New // can't pay already paid invoices
    );

    // in case of any throws the contract's state will be reverted
    order.status = EnumOrderStatus.Process;
    order.carrier = invoice.sender; // if the customer paid the invoice, it means that he chose the carrier
    order.invoiceId = invoiceId;
    invoice.status = (deposit != 0 ? EnumInvoiceStatus.Deposit : EnumInvoiceStatus.Prepaid);
    invoice.depositHash = depositHash; // even if deposit = 0, can be usefull for changing order state

    if (invoice.currency == EnumCurrency.ETH) {
      require(msg.value == amount); // not enough or too much funds

      uint balanceBefore = address(this).balance; // for asserts
      uint fee = 0;

      if (prepayment != 0) {
        fee = getFee(prepayment);
        fees = fees.add(fee);

        invoice.sender.transfer(prepayment.sub(fee));
      }

      uint balanceAfter = address(this).balance;

      assert(balanceAfter == balanceBefore.sub(prepayment).add(fee)); // msg.value is added to balanceBefore
    }

    if (invoice.currency == EnumCurrency.OSLIK) { // no fee
      require(msg.value == 0); // prevent loss of ETH
      require(oslikToken.allowance(msg.sender, this) >= amount); // check allowance

      uint balanceOfBefore = oslikToken.balanceOf(this);

      if (prepayment != 0) {
        oslikToken.safeTransferFrom(msg.sender, invoice.sender, prepayment);
      }

      if (deposit != 0) {
        oslikToken.safeTransferFrom(msg.sender, this, deposit);
      }

      uint balanceOfAfter = oslikToken.balanceOf(this);

      assert(balanceOfAfter == balanceOfBefore.add(deposit));
    }

    emit EventPayment(invoiceId);
  }




  function getOrdersCount() public view returns (uint) {
    return orders.length;
  }

  function getOffersCount() public view returns (uint) {
    return offers.length;
  }

  function getOrderOffersCount(uint orderId) public view returns (uint) {
    return orders[orderId].offerIds.length;
  }

  function getInvoicesCount() public view returns (uint) {
    return invoices.length;
  }
}
