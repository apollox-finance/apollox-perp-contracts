// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../utils/Constants.sol";
import "../interfaces/IBrokerManager.sol";
import "../libraries/LibBrokerManager.sol";
import "../libraries/LibAccessControlEnumerable.sol";

contract BrokerManagerFacet is IBrokerManager {

    function initBrokerManagerFacet(
        uint24 id, uint16 commissionP, address receiver,
        string calldata name, string calldata url
    ) external {
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        require(commissionP >= 0 && commissionP <= Constants.MAX_COMMISSION_P, "BrokerManagerFacet: Invalid commissionP");
        require(receiver != address(0), "BrokerManagerFacet: receiver cannot be 0 address");
        LibAccessControlEnumerable.checkRole(Constants.DEPLOYER_ROLE);
        LibBrokerManager.initialize(id, commissionP, receiver, name, url);
    }

    function addBroker(
        uint24 id, uint16 commissionP, address receiver,
        string calldata name, string calldata url
    ) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        require(commissionP >= 0 && commissionP <= Constants.MAX_COMMISSION_P, "BrokerManagerFacet: Invalid commissionP");
        require(receiver != address(0), "BrokerManagerFacet: receiver cannot be 0 address");
        LibBrokerManager.addBroker(id, commissionP, receiver, name, url);
    }

    function removeBroker(uint24 id) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        LibBrokerManager.removeBroker(id);
    }

    function updateBrokerCommissionP(uint24 id, uint16 commissionP) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        require(commissionP >= 0 && commissionP <= Constants.MAX_COMMISSION_P, "BrokerManagerFacet: Invalid commissionP");
        LibBrokerManager.updateBrokerCommissionP(id, commissionP);
    }

    function updateBrokerReceiver(uint24 id, address receiver) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        require(receiver != address(0), "BrokerManagerFacet: receiver cannot be 0 address");
        LibBrokerManager.updateBrokerReceiver(id, receiver);
    }

    function updateBrokerName(uint24 id, string calldata name) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        LibBrokerManager.updateBrokerName(id, name);
    }

    function updateBrokerUrl(uint24 id, string calldata url) external override {
        LibAccessControlEnumerable.checkRole(Constants.ADMIN_ROLE);
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        LibBrokerManager.updateBrokerUrl(id, url);
    }

    function getBrokerById(uint24 id) external view override returns (BrokerInfo memory) {
        LibBrokerManager.BrokerManagerStorage storage bms = LibBrokerManager.brokerManagerStorage();
        return _getBrokerById(bms, id);
    }

    function _getBrokerById(LibBrokerManager.BrokerManagerStorage storage bms, uint24 id) private view returns (BrokerInfo memory) {
        LibBrokerManager.Broker memory b = bms.brokers[id];
        address[] memory tokens = bms.brokerCommissionTokens[id];
        CommissionInfo[] memory commissions = new CommissionInfo[](tokens.length);
        for (uint i; i < tokens.length; i++) {
            LibBrokerManager.Commission memory c = bms.brokerCommissions[id][tokens[i]];
            commissions[i] = CommissionInfo(tokens[i], c.total, c.pending);
        }
        return BrokerInfo(b.name, b.url, b.receiver, b.id, b.commissionP, commissions);
    }

    function brokers(uint start, uint8 length) external view override returns (BrokerInfo[] memory) {
        LibBrokerManager.BrokerManagerStorage storage bms = LibBrokerManager.brokerManagerStorage();
        uint24[] memory ids = bms.brokerIds;
        if (start >= ids.length || length == 0) {
            return new BrokerInfo[](0);
        }
        uint count = length <= ids.length - start ? length : ids.length - start;
        BrokerInfo[] memory brokerInfos = new BrokerInfo[](count);
        for (uint i; i < count; i++) {
            brokerInfos[i] = _getBrokerById(bms, ids[start + i]);
        }
        return brokerInfos;
    }

    function withdrawCommission(uint24 id) external override {
        require(id > 0, "BrokerManagerFacet: Id must be greater than 0");
        LibBrokerManager.withdrawCommission(id);
    }
}
