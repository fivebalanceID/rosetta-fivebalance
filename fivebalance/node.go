// Copyright 2020 Coinbase, Inc.
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

package fivebalance

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/fivebalanceID/rosetta-fivebalance/utils"

	"golang.org/x/sync/errgroup"
)

const (
	fivebalancedLogger       = "fivebalanced"
	fivebalancedStdErrLogger = "fivebalanced stderr"
)

func logPipe(ctx context.Context, pipe io.ReadCloser, identifier string) error {
	logger := utils.ExtractLogger(ctx, identifier)
	reader := bufio.NewReader(pipe)
	for {
		str, err := reader.ReadString('\n')
		if err != nil {
			logger.Warnw("closing logger", "error", err)
			return err
		}

		message := strings.ReplaceAll(str, "\n", "")
		messages := strings.SplitAfterN(message, " ", 2)

		// Trim the timestamp from the log if it exists
		if len(messages) > 1 {
			message = messages[1]
		}

		// Print debug log if from fivebalancedLogger
		if identifier == fivebalancedLogger {
			logger.Debugw(message)
			continue
		}

		logger.Warnw(message)
	}
}

// StartFivebalanced starts a fivebalanced daemon in another goroutine
// and logs the results to the console.
func StartFivebalanced(ctx context.Context, configPath string, g *errgroup.Group) error {
	logger := utils.ExtractLogger(ctx, "fivebalanced")
	cmd := exec.Command(
		"/app/fivebalanced",
		fmt.Sprintf("--conf=%s", configPath),
	) // #nosec G204

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	g.Go(func() error {
		return logPipe(ctx, stdout, fivebalancedLogger)
	})

	g.Go(func() error {
		return logPipe(ctx, stderr, fivebalancedStdErrLogger)
	})

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("%w: unable to start fivebalanced", err)
	}

	g.Go(func() error {
		<-ctx.Done()

		logger.Warnw("sending interrupt to fivebalanced")
		return cmd.Process.Signal(os.Interrupt)
	})

	return cmd.Wait()
}
