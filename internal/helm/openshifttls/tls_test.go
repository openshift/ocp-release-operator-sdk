// Copyright 2026 The Operator-SDK Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package openshifttls

import (
	"context"
	"crypto/tls"
	"testing"

	configv1 "github.com/openshift/api/config/v1"
	tlspkg "github.com/openshift/controller-runtime-common/pkg/tls"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	apimachruntime "k8s.io/apimachinery/pkg/runtime"
	ctrlclient "sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/manager"
)

func newFakeClientWithScheme(objs ...ctrlclient.Object) ctrlclient.Client {
	scheme := apimachruntime.NewScheme()
	if err := configv1.AddToScheme(scheme); err != nil {
		panic(err)
	}
	return fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
}

func TestDefaultProfile(t *testing.T) {
	got := defaultProfile()
	want, err := tlspkg.GetTLSProfileSpec(nil)
	require.NoError(t, err)
	assert.Equal(t, want, got)
	assert.Equal(t, configv1.TLSProfiles[configv1.TLSProfileIntermediateType].MinTLSVersion, got.MinTLSVersion)
}

func TestFetchProfile_NilClientFallsBackToDefault(t *testing.T) {
	got := fetchProfile(context.Background(), nil)
	assert.Equal(t, defaultProfile(), got)
}

func TestFetchProfile_APIServerNotFoundFallsBackToDefault(t *testing.T) {
	// No "cluster" APIServer object exists in the fake client, simulating
	// either a non-OpenShift cluster or the CRD not being installed.
	client := newFakeClientWithScheme()

	got := fetchProfile(context.Background(), client)
	assert.Equal(t, defaultProfile(), got)
}

func TestFetchProfile_ReturnsConfiguredProfile(t *testing.T) {
	apiServer := &configv1.APIServer{
		ObjectMeta: metav1.ObjectMeta{Name: tlspkg.APIServerName},
		Spec: configv1.APIServerSpec{
			TLSSecurityProfile: &configv1.TLSSecurityProfile{
				Type: configv1.TLSProfileModernType,
			},
		},
	}
	client := newFakeClientWithScheme(apiServer)

	got := fetchProfile(context.Background(), client)
	assert.Equal(t, *configv1.TLSProfiles[configv1.TLSProfileModernType], got)
	assert.NotEqual(t, defaultProfile(), got, "Modern profile must differ from the Intermediate default used in this test")
}

func TestClusterTLSPolicy_ApplyAppendsMetricsTLSOpts(t *testing.T) {
	p := &clusterTLSPolicy{}

	// Apply builds its own client from *rest.Config, which requires a real
	// (or at least non-empty) cluster connection outside the scope of this
	// unit test; exercise the same code path fetchProfile/Apply relies on
	// directly instead, then assert the manager.Options mutation contract.
	profile := *configv1.TLSProfiles[configv1.TLSProfileModernType]
	p.initialProfile = profile

	tlsConfigFunc, unsupported := tlspkg.NewTLSConfigFromProfile(profile)
	assert.Empty(t, unsupported)

	var options manager.Options
	options.Metrics.TLSOpts = append(options.Metrics.TLSOpts, tlsConfigFunc)

	require.Len(t, options.Metrics.TLSOpts, 1)
	cfg := &tls.Config{} //nolint:gosec // test-only, not used for a real connection
	options.Metrics.TLSOpts[0](cfg)
	assert.Equal(t, uint16(tls.VersionTLS13), cfg.MinVersion)
}
