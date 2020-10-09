/*
Copyright Sparebanken Vest

Based on the Kubernetes controller example at
https://github.com/kubernetes/sample-controller

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Based on https://github.com/Azure/aad-pod-identity
*/

package main

import (
	"github.com/Azure/azure-sdk-for-go/services/compute/mgmt/2019-12-01/compute"
)

// IdentityHolder represents a resource that contains an Identity object
// This is used to be able to generically intract with multiple resource types (e.g. VirtualMachine and VirtualMachineScaleSet)
// which each contain an identity.
type IdentityHolder interface {
	IdentityInfo() IdentityInfo
	ResetIdentity() IdentityInfo
}

// IdentityInfo is used to interact with different implementations of Azure compute identities.
// This is needed because different Azure resource types (e.g. VirtualMachine and VirtualMachineScaleSet)
// have different identity types.
// This abstracts those differences.
type IdentityInfo interface {
	GetUserIdentityList() []string
	SetUserIdentities(map[string]bool) bool
	RemoveUserIdentity(string) bool
}

// getUpdatedResourceIdentityType returns the new resource identity type
// to be set on the VM/VMSS based on current type
func getUpdatedResourceIdentityType(identityType compute.ResourceIdentityType) compute.ResourceIdentityType {
	switch identityType {
	case "", compute.ResourceIdentityTypeNone, compute.ResourceIdentityTypeUserAssigned:
		return compute.ResourceIdentityTypeUserAssigned
	case compute.ResourceIdentityTypeSystemAssigned, compute.ResourceIdentityTypeSystemAssignedUserAssigned:
		return compute.ResourceIdentityTypeSystemAssignedUserAssigned
	default:
		return compute.ResourceIdentityTypeNone
	}
}
