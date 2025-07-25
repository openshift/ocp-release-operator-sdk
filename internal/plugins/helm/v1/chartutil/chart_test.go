// Copyright 2020 The Operator-SDK Authors
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

package chartutil_test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"helm.sh/helm/v3/pkg/chart"
	"helm.sh/helm/v3/pkg/repo/repotest"

	"github.com/operator-framework/operator-sdk/internal/plugins/helm/v1/chartutil"
)

func TestChart(t *testing.T) {
	srv, err := repotest.NewTempServerWithCleanup(t, "testdata/*.tgz")
	if err != nil {
		t.Fatalf("Failed to create new temp server: %s", err)
	}
	defer srv.Stop()

	if err := srv.LinkIndices(); err != nil {
		t.Fatalf("Failed to link server indices: %s", err)
	}

	const (
		chartName          = "test-chart"
		latestVersion      = "1.2.3"
		previousVersion    = "1.2.0"
		nonExistentVersion = "0.0.1"
		customKind         = "MyApp"
		customExpectName   = "myapp"
	)

	testCases := []createChartTestCase{
		{
			name:      "from scaffold no apiVersion",
			expectErr: true,
		},
		{
			name:             "version without helm chart",
			helmChartVersion: latestVersion,
			expectErr:        true,
		},
		{
			name:          "repo without helm chart",
			helmChartRepo: srv.URL(),
			expectErr:     true,
		},
		{
			name:             "non-existent version",
			helmChart:        "test/" + chartName,
			helmChartVersion: nonExistentVersion,
			expectErr:        true,
		},
		{
			name:               "from scaffold with kind",
			kind:               customKind,
			expectChartName:    customExpectName,
			expectChartVersion: "0.1.0",
		},
		{
			name:               "from directory",
			helmChart:          filepath.Join(".", "testdata", chartName),
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from archive",
			helmChart:          filepath.Join(".", "testdata", fmt.Sprintf("%s-%s.tgz", chartName, latestVersion)),
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from url",
			helmChart:          fmt.Sprintf("%s/%s-%s.tgz", srv.URL(), chartName, latestVersion),
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from repo and name implicit latest",
			helmChart:          "test/" + chartName,
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from repo and name implicit latest with kind",
			helmChart:          "test/" + chartName,
			kind:               customKind,
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from repo and name explicit latest",
			helmChart:          "test/" + chartName,
			helmChartVersion:   latestVersion,
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from repo and name explicit previous",
			helmChart:          "test/" + chartName,
			helmChartVersion:   previousVersion,
			expectChartName:    chartName,
			expectChartVersion: previousVersion,
		},
		{
			name:               "from name and repo url implicit latest",
			helmChart:          chartName,
			helmChartRepo:      srv.URL(),
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from name and repo url explicit latest",
			helmChart:          chartName,
			helmChartRepo:      srv.URL(),
			helmChartVersion:   latestVersion,
			expectChartName:    chartName,
			expectChartVersion: latestVersion,
		},
		{
			name:               "from name and repo url explicit previous",
			helmChart:          chartName,
			helmChartRepo:      srv.URL(),
			helmChartVersion:   previousVersion,
			expectChartName:    chartName,
			expectChartVersion: previousVersion,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			runTestCase(t, srv.Root(), tc)
		})
	}
}

type createChartTestCase struct {
	name string

	kind             string
	helmChart        string
	helmChartVersion string
	helmChartRepo    string

	expectChartName    string
	expectChartVersion string
	expectErr          bool
}

func runTestCase(t *testing.T, testDir string, tc createChartTestCase) {
	outputDir := filepath.Join(testDir, "output")
	assert.NoError(t, os.Mkdir(outputDir, 0755))
	defer os.RemoveAll(outputDir)

	os.Setenv("XDG_CONFIG_HOME", filepath.Join(testDir, ".config"))
	os.Setenv("XDG_CACHE_HOME", filepath.Join(testDir, ".cache"))
	os.Setenv("HELM_REPOSITORY_CONFIG", filepath.Join(testDir, "repositories.yaml"))
	os.Setenv("HELM_REPOSITORY_CACHE", filepath.Join(testDir))
	defer os.Unsetenv("XDG_CONFIG_HOME")
	defer os.Unsetenv("XDG_CACHE_HOME")
	defer os.Unsetenv("HELM_REPOSITORY_CONFIG")
	defer os.Unsetenv("HELM_REPOSITORY_CACHE")

	var (
		chrt *chart.Chart
		err  error
	)
	if tc.helmChart != "" {
		opts := chartutil.Options{
			Chart:   tc.helmChart,
			Version: tc.helmChartVersion,
			Repo:    tc.helmChartRepo,
		}
		chrt, err = chartutil.LoadChart(opts)
	} else {
		chrt, err = chartutil.NewChart(strings.ToLower(tc.kind))
	}

	if tc.expectErr {
		assert.Error(t, err)
		return
	}

	if !assert.NoError(t, err) {
		return
	}
	assert.Equal(t, tc.expectChartName, chrt.Name())
	assert.Equal(t, tc.expectChartVersion, chrt.Metadata.Version)

	_, chartPath, err := chartutil.ScaffoldChart(chrt, outputDir)
	assert.NoError(t, err)
	assert.Equal(t, filepath.Join(chartutil.HelmChartsDir, tc.expectChartName), chartPath)
}

// TestCVE2025_53547_Protection tests that ScaffoldChart properly detects and blocks symlinked Chart.lock files.
// This validates the CVE-2025-53547 mitigation implemented in validateForSymlink function.
// Reference: https://github.com/helm/helm/security/advisories/GHSA-557j-xg8c-q2mm
func TestCVE2025_53547_Protection(t *testing.T) {
	tests := []struct {
		name                  string
		setupAfterScaffolding func(string) error // Setup function called after initial scaffolding
		expectCVEError        bool
	}{
		{
			name: "safe chart with no Chart.lock",
			setupAfterScaffolding: func(scaffoldedChartPath string) error {
				// Remove any Chart.lock file
				chartLockPath := filepath.Join(scaffoldedChartPath, "Chart.lock")
				os.Remove(chartLockPath)
				return nil
			},
			expectCVEError: false,
		},
		{
			name: "safe chart with regular Chart.lock",
			setupAfterScaffolding: func(scaffoldedChartPath string) error {
				// Ensure a regular (non-symlinked) Chart.lock file exists
				chartLockPath := filepath.Join(scaffoldedChartPath, "Chart.lock")

				if _, err := os.Stat(chartLockPath); os.IsNotExist(err) {
					return fmt.Errorf("chart.lock doesn't exist at %s: %v", chartLockPath, err)
				} else if err != nil {
					return err
				}
				return nil
			},
			expectCVEError: false,
		},
		{
			name: "CVE-2025-53547: symlinked Chart.lock attack",
			setupAfterScaffolding: func(scaffoldedChartPath string) error {
				// Create target file for symlink
				targetFile := filepath.Join(scaffoldedChartPath, "target.yaml")
				targetContent := "dependencies: []"
				if err := os.WriteFile(targetFile, []byte(targetContent), 0644); err != nil {
					return err
				}

				// Remove any existing Chart.lock and create symlink
				chartLockPath := filepath.Join(scaffoldedChartPath, "Chart.lock")
				os.Remove(chartLockPath) // Remove if exists
				return os.Symlink("target.yaml", chartLockPath)
			},
			expectCVEError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create temporary directories
			tmpProjectDir, err := os.MkdirTemp("", "test-project-cve")
			assert.NoError(t, err)
			defer os.RemoveAll(tmpProjectDir)

			tmpChartDir, err := os.MkdirTemp("", "test-chart-cve")
			assert.NoError(t, err)
			defer os.RemoveAll(tmpChartDir)

			// Step 1: Create chart with dependencies to generate Chart.lock
			chartYaml := `apiVersion: v2
name: test-chart
version: 1.0.0
appVersion: 1.0.0
description: Test chart for CVE-2025-53547 testing
type: application
dependencies:
  - name: common
    version: "2.0.0"
    repository: "oci://registry-1.docker.io/bitnamicharts"
`
			err = os.WriteFile(filepath.Join(tmpChartDir, "Chart.yaml"), []byte(chartYaml), 0644)
			assert.NoError(t, err)

			// Step 2: Initial scaffolding
			chrt, err := chartutil.LoadChart(chartutil.Options{Chart: tmpChartDir})
			assert.NoError(t, err)
			assert.NotNil(t, chrt)

			_, _, err = chartutil.ScaffoldChart(chrt, tmpProjectDir)
			assert.NoError(t, err)

			// Step 3: Setup test scenario in scaffolded chart
			scaffoldedChartPath := filepath.Join(tmpProjectDir, chartutil.HelmChartsDir, chrt.Name())
			err = tt.setupAfterScaffolding(scaffoldedChartPath)
			assert.NoError(t, err)

			// Step 4: Try to scaffold again
			chrt2, err := chartutil.LoadChart(chartutil.Options{Chart: scaffoldedChartPath})
			assert.NoError(t, err)
			assert.NotNil(t, chrt2)

			_, _, err = chartutil.ScaffoldChart(chrt2, tmpProjectDir)

			if tt.expectCVEError {
				// CVE attack case: should fail with CVE protection message
				assert.Error(t, err)
				assert.Contains(t, err.Error(), "the Chart.lock file is a symlink to")
			} else {
				assert.NoError(t, err)
			}
		})
	}
}
