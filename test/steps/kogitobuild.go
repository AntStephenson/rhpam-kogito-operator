// Copyright 2020 Red Hat, Inc. and/or its affiliates
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package steps

import (
	"path/filepath"

	"github.com/kiegroup/kogito-operator/api"
	"github.com/kiegroup/rhpam-kogito-operator/test/framework"

	"github.com/cucumber/godog"
	"github.com/kiegroup/kogito-operator/test/config"
	bddtypes "github.com/kiegroup/kogito-operator/test/types"
	"github.com/kiegroup/rhpam-kogito-operator/test/steps/mappers"
)

/*
	DataTable for KogitoBuild:
	| config        | native     | enabled/disabled |
	| build-request | cpu/memory | value            |
	| build-limit   | cpu/memory | value            |
*/

func registerKogitoBuildSteps(ctx *godog.ScenarioContext, data *Data) {
	// Deploy steps
	ctx.Step(`^Build (quarkus|springboot) example service "([^"]*)" with configuration:$`, data.buildExampleServiceWithConfiguration)
	ctx.Step(`^Build binary (quarkus|springboot) service "([^"]*)" with configuration:$`, data.buildBinaryServiceWithConfiguration)
}

// Build service steps

func (data *Data) buildExampleServiceWithConfiguration(runtimeType, contextDir string, table *godog.Table) error {
	buildHolder, err := getKogitoBuildConfiguredStub(data.Namespace, runtimeType, filepath.Base(contextDir), table)
	if err != nil {
		return err
	}

	buildHolder.KogitoBuild.GetSpec().SetType(api.RemoteSourceBuildType)
	buildHolder.KogitoBuild.GetSpec().GetGitSource().SetURI(config.GetExamplesRepositoryURI())
	buildHolder.KogitoBuild.GetSpec().GetGitSource().SetContextDir(contextDir)
	if ref := config.GetExamplesRepositoryRef(); len(ref) > 0 {
		buildHolder.KogitoBuild.GetSpec().GetGitSource().SetReference(ref)
	}

	return framework.DeployKogitoBuild(data.Namespace, buildHolder)
}

func (data *Data) buildBinaryServiceWithConfiguration(runtimeType, serviceName string, table *godog.Table) error {
	buildHolder, err := getKogitoBuildConfiguredStub(data.Namespace, runtimeType, serviceName, table)
	if err != nil {
		return err
	}

	buildHolder.KogitoBuild.GetSpec().SetType(api.BinaryBuildType)

	return framework.DeployKogitoBuild(data.Namespace, buildHolder)
}

// Misc methods

// getKogitoBuildConfiguredStub Get KogitoBuildHolder initialized from table if provided
func getKogitoBuildConfiguredStub(namespace, runtimeType, serviceName string, table *godog.Table) (buildHolder *bddtypes.KogitoBuildHolder, err error) {
	kogitoBuild := framework.GetKogitoBuildStub(namespace, runtimeType, serviceName)
	kogitoRuntime := framework.GetKogitoRuntimeStub(namespace, runtimeType, serviceName, "")

	buildHolder = &bddtypes.KogitoBuildHolder{
		KogitoServiceHolder: &bddtypes.KogitoServiceHolder{KogitoService: kogitoRuntime},
		KogitoBuild:         kogitoBuild,
	}

	if table != nil {
		err = mappers.MapKogitoBuildTable(table, buildHolder)
	}

	framework.SetupKogitoBuildImageStreams(kogitoBuild)

	return buildHolder, err
}
