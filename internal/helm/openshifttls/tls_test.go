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
	"errors"
	"testing"

	configv1 "github.com/openshift/api/config/v1"
	tlspkg "github.com/openshift/controller-runtime-common/pkg/tls"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	apimachruntime "k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/rest"
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

func newFakeAPIServer(profileType configv1.TLSProfileType) *configv1.APIServer {
	return &configv1.APIServer{
		ObjectMeta: metav1.ObjectMeta{Name: tlspkg.APIServerName},
		Spec: configv1.APIServerSpec{
			TLSSecurityProfile: &configv1.TLSSecurityProfile{
				Type: profileType,
			},
		},
	}
}

// TestClusterTLSPolicy_Apply exercises clusterTLSPolicy.Apply and covers the 3 scenarios relevant for TLS compliance
// fakeClient is used to simulate the response of the client to the APIServer resource
func TestClusterTLSPolicy_Apply(t *testing.T) {
	testCases := []struct {
		name                       string
		profileType                configv1.TLSProfileType
		apiServerMissing           bool
		wantProfileSourceAvailable bool
		wantMinVersion             uint16
		wantCipherSuite            bool
	}{
		{
			name:                       "Modern profile sets MinVersion only",
			profileType:                configv1.TLSProfileModernType,
			wantProfileSourceAvailable: true,
			wantMinVersion:             tls.VersionTLS13,
			wantCipherSuite:            false,
		},
		{
			name:                       "Intermediate profile sets MinVersion and CipherSuites",
			profileType:                configv1.TLSProfileIntermediateType,
			wantProfileSourceAvailable: true,
			wantMinVersion:             tls.VersionTLS12,
			wantCipherSuite:            true,
		},
		{
			name:                       "missing APIServer object falls back open to default (Intermediate) profile",
			apiServerMissing:           true,
			wantProfileSourceAvailable: false,
			wantMinVersion:             tls.VersionTLS12,
			wantCipherSuite:            true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			fakeClient := newFakeClientWithScheme() // no APIServer object: simulates non-OpenShift / CRD missing.
			if !tc.apiServerMissing {
				fakeClient = newFakeClientWithScheme(newFakeAPIServer(tc.profileType))
			}
			p := &clusterTLSPolicy{
				client: func(*rest.Config, ctrlclient.Options) (ctrlclient.Client, error) {
					return fakeClient, nil
				},
			}

			options, err := p.Apply(context.Background(), &rest.Config{}, manager.Options{Scheme: apimachruntime.NewScheme()})
			require.NoError(t, err)
			assert.Equal(t, tc.wantProfileSourceAvailable, p.profileSourceAvailable)

			require.Len(t, options.Metrics.TLSOpts, 1, "a TLS config callback must always be appended, even when falling back to the default profile")
			cfg := &tls.Config{} //nolint:gosec // test-only, not used for a real connection
			options.Metrics.TLSOpts[0](cfg)

			assert.Equal(t, tc.wantMinVersion, cfg.MinVersion)
			if tc.wantCipherSuite {
				assert.NotEmpty(t, cfg.CipherSuites, "expected CipherSuites to be set for a sub-TLS1.3 profile")
			} else {
				assert.Empty(t, cfg.CipherSuites, "TLS 1.3 cipher suites aren't configurable; CipherSuites should be left unset")
			}
		})
	}
}

func TestClusterTLSPolicy_Apply_ClientConstructionFailureReturnsError(t *testing.T) {
	wantErr := errors.New("boom: cannot construct client")
	p := &clusterTLSPolicy{
		client: func(*rest.Config, ctrlclient.Options) (ctrlclient.Client, error) {
			return nil, wantErr
		},
	}

	options, err := p.Apply(context.Background(), &rest.Config{}, manager.Options{Scheme: apimachruntime.NewScheme()})
	require.Error(t, err, "Apply must surface a client-construction failure rather than failing open")
	assert.ErrorIs(t, err, wantErr)
	assert.False(t, p.profileSourceAvailable)
	assert.Empty(t, options.Metrics.TLSOpts, "no TLS config should be appended when the client couldn't be constructed")
}

func TestClusterTLSPolicy_Watch_SkipsWhenProfileSourceUnavailable(t *testing.T) {
	p := &clusterTLSPolicy{profileSourceAvailable: false}
	err := p.WatchIfProfileAvailable(context.Background(), nil, func() {})
	assert.NoError(t, err)
}
