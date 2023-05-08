// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibAccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/IAccessControlEnumerable.sol";

contract AccessControlEnumerableFacet is IAccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return LibAccessControlEnumerable.hasRole(role, account);
    }

    function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
        LibAccessControlEnumerable.AccessControlStorage storage acs = LibAccessControlEnumerable.accessControlStorage();
        return acs.roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) external override {
        LibAccessControlEnumerable.checkRole(getRoleAdmin(role), msg.sender);
        LibAccessControlEnumerable.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external override {
        LibAccessControlEnumerable.checkRole(getRoleAdmin(role), msg.sender);
        LibAccessControlEnumerable.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external override {
        require(account == msg.sender, "AccessControlEnumerableFacet: can only renounce roles for self");
        LibAccessControlEnumerable.revokeRole(role, account);
    }

    function getRoleMember(bytes32 role, uint256 index) external view override returns (address) {
        LibAccessControlEnumerable.AccessControlStorage storage acs = LibAccessControlEnumerable.accessControlStorage();
        return acs.roleMembers[role].at(index);
    }

    function getRoleMemberCount(bytes32 role) external view override returns (uint256) {
        LibAccessControlEnumerable.AccessControlStorage storage acs = LibAccessControlEnumerable.accessControlStorage();
        return acs.roleMembers[role].length();
    }
}
