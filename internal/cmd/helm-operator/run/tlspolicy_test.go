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

package run

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/manager"
)

// stubTLSPolicy is a minimal ClusterTLSPolicy used to verify the
// registration/hook contract without depending on any real implementation
// (e.g. the downstream-only openshifttls package).
type stubTLSPolicy struct {
	applyCalled, watchCalled bool
	applyErr, watchErr       error
}

func (s *stubTLSPolicy) Apply(_ context.Context, _ *rest.Config, options manager.Options) (manager.Options, error) {
	s.applyCalled = true
	return options, s.applyErr
}

func (s *stubTLSPolicy) WatchIfProfileAvailable(_ context.Context, _ manager.Manager, _ context.CancelFunc) error {
	s.watchCalled = true
	return s.watchErr
}

// withRegisteredTLSPolicy registers p for the duration of the test and
// restores the previous value on cleanup, so tests don't leak global state
// into each other or into non-TLS-policy tests in this package.
func withRegisteredTLSPolicy(t *testing.T, p ClusterTLSPolicy) {
	t.Helper()
	previous := registeredTLSPolicy
	t.Cleanup(func() { registeredTLSPolicy = previous })
	registeredTLSPolicy = p
}

func TestRegisterClusterTLSPolicy(t *testing.T) {
	require.Nil(t, registeredTLSPolicy)

	policy := &stubTLSPolicy{}
	withRegisteredTLSPolicy(t, policy)

	assert.Same(t, ClusterTLSPolicy(policy), registeredTLSPolicy)
}

func TestRegisterClusterTLSPolicy_PanicsOnSecondRegistration(t *testing.T) {
	first := &stubTLSPolicy{}
	withRegisteredTLSPolicy(t, first)

	second := &stubTLSPolicy{}
	assert.PanicsWithValue(t,
		"ClusterTLSPolicy already registered; only one implementation may be registered",
		func() { RegisterClusterTLSPolicy(second) },
	)
	assert.Same(t, ClusterTLSPolicy(first), registeredTLSPolicy, "the original registration must be left untouched after a rejected second attempt")
}
