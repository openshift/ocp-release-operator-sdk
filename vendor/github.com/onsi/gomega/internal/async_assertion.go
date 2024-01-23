package internal

import (
<<<<<<< HEAD
=======
	"context"
>>>>>>> ef22b1c6a (Bump go-git)
	"errors"
	"fmt"
	"reflect"
	"runtime"
	"time"

	"github.com/onsi/gomega/types"
)

<<<<<<< HEAD
=======
var errInterface = reflect.TypeOf((*error)(nil)).Elem()
var gomegaType = reflect.TypeOf((*types.Gomega)(nil)).Elem()
var contextType = reflect.TypeOf(new(context.Context)).Elem()

type formattedGomegaError interface {
	FormattedGomegaError() string
}

type asyncPolledActualError struct {
	message string
}

func (err *asyncPolledActualError) Error() string {
	return err.message
}

func (err *asyncPolledActualError) FormattedGomegaError() string {
	return err.message
}

type contextWithAttachProgressReporter interface {
	AttachProgressReporter(func() string) func()
}

type asyncGomegaHaltExecutionError struct{}

func (a asyncGomegaHaltExecutionError) GinkgoRecoverShouldIgnoreThisPanic() {}
func (a asyncGomegaHaltExecutionError) Error() string {
	return `An assertion has failed in a goroutine.  You should call 

    defer GinkgoRecover()

at the top of the goroutine that caused this panic.  This will allow Ginkgo and Gomega to correctly capture and manage this panic.`
}

>>>>>>> ef22b1c6a (Bump go-git)
type AsyncAssertionType uint

const (
	AsyncAssertionTypeEventually AsyncAssertionType = iota
	AsyncAssertionTypeConsistently
)

type AsyncAssertion struct {
	asyncType AsyncAssertionType

	actualIsFunc bool
	actualValue  interface{}
	actualFunc   func() ([]reflect.Value, error)

<<<<<<< HEAD
	timeoutInterval time.Duration
	pollingInterval time.Duration
	offset          int
	g               *Gomega
}

func NewAsyncAssertion(asyncType AsyncAssertionType, actualInput interface{}, g *Gomega, timeoutInterval time.Duration, pollingInterval time.Duration, offset int) *AsyncAssertion {
	out := &AsyncAssertion{
		asyncType:       asyncType,
		timeoutInterval: timeoutInterval,
		pollingInterval: pollingInterval,
		offset:          offset,
		g:               g,
=======
	timeoutInterval    time.Duration
	pollingInterval    time.Duration
	mustPassRepeatedly int
	ctx                context.Context
	offset             int
	g                  *Gomega
}

func NewAsyncAssertion(asyncType AsyncAssertionType, actualInput interface{}, g *Gomega, timeoutInterval time.Duration, pollingInterval time.Duration, mustPassRepeatedly int, ctx context.Context, offset int) *AsyncAssertion {
	out := &AsyncAssertion{
		asyncType:          asyncType,
		timeoutInterval:    timeoutInterval,
		pollingInterval:    pollingInterval,
		mustPassRepeatedly: mustPassRepeatedly,
		offset:             offset,
		ctx:                ctx,
		g:                  g,
>>>>>>> ef22b1c6a (Bump go-git)
	}

	switch actualType := reflect.TypeOf(actualInput); {
	case actualInput == nil || actualType.Kind() != reflect.Func:
		out.actualValue = actualInput
	case actualType.NumIn() == 0 && actualType.NumOut() > 0:
		out.actualIsFunc = true
		out.actualFunc = func() ([]reflect.Value, error) {
			return reflect.ValueOf(actualInput).Call([]reflect.Value{}), nil
		}
	case actualType.NumIn() == 1 && actualType.In(0).Implements(reflect.TypeOf((*types.Gomega)(nil)).Elem()):
		out.actualIsFunc = true
		out.actualFunc = func() (values []reflect.Value, err error) {
			var assertionFailure error
			assertionCapturingGomega := NewGomega(g.DurationBundle).ConfigureWithFailHandler(func(message string, callerSkip ...int) {
				skip := 0
				if len(callerSkip) > 0 {
					skip = callerSkip[0]
				}
				_, file, line, _ := runtime.Caller(skip + 1)
				assertionFailure = fmt.Errorf("Assertion in callback at %s:%d failed:\n%s", file, line, message)
				panic("stop execution")
			})

			defer func() {
				if actualType.NumOut() == 0 {
					if assertionFailure == nil {
						values = []reflect.Value{reflect.Zero(reflect.TypeOf((*error)(nil)).Elem())}
					} else {
						values = []reflect.Value{reflect.ValueOf(assertionFailure)}
					}
				} else {
					err = assertionFailure
				}
				if e := recover(); e != nil && assertionFailure == nil {
					panic(e)
				}
			}()

			values = reflect.ValueOf(actualInput).Call([]reflect.Value{reflect.ValueOf(assertionCapturingGomega)})
			return
		}
	default:
		msg := fmt.Sprintf("The function passed to Gomega's async assertions should either take no arguments and return values, or take a single Gomega interface that it can use to make assertions within the body of the function.  When taking a Gomega interface the function can optionally return values or return nothing.  The function you passed takes %d arguments and returns %d values.", actualType.NumIn(), actualType.NumOut())
		g.Fail(msg, offset+4)
	}

	return out
}

func (assertion *AsyncAssertion) WithOffset(offset int) types.AsyncAssertion {
	assertion.offset = offset
	return assertion
}

func (assertion *AsyncAssertion) WithTimeout(interval time.Duration) types.AsyncAssertion {
	assertion.timeoutInterval = interval
	return assertion
}

func (assertion *AsyncAssertion) WithPolling(interval time.Duration) types.AsyncAssertion {
	assertion.pollingInterval = interval
	return assertion
}

<<<<<<< HEAD
=======
func (assertion *AsyncAssertion) Within(timeout time.Duration) types.AsyncAssertion {
	assertion.timeoutInterval = timeout
	return assertion
}

func (assertion *AsyncAssertion) ProbeEvery(interval time.Duration) types.AsyncAssertion {
	assertion.pollingInterval = interval
	return assertion
}

func (assertion *AsyncAssertion) WithContext(ctx context.Context) types.AsyncAssertion {
	assertion.ctx = ctx
	return assertion
}

func (assertion *AsyncAssertion) WithArguments(argsToForward ...interface{}) types.AsyncAssertion {
	assertion.argsToForward = argsToForward
	return assertion
}

func (assertion *AsyncAssertion) MustPassRepeatedly(count int) types.AsyncAssertion {
	assertion.mustPassRepeatedly = count
	return assertion
}

>>>>>>> ef22b1c6a (Bump go-git)
func (assertion *AsyncAssertion) Should(matcher types.GomegaMatcher, optionalDescription ...interface{}) bool {
	assertion.g.THelper()
	vetOptionalDescription("Asynchronous assertion", optionalDescription...)
	return assertion.match(matcher, true, optionalDescription...)
}

func (assertion *AsyncAssertion) ShouldNot(matcher types.GomegaMatcher, optionalDescription ...interface{}) bool {
	assertion.g.THelper()
	vetOptionalDescription("Asynchronous assertion", optionalDescription...)
	return assertion.match(matcher, false, optionalDescription...)
}

func (assertion *AsyncAssertion) buildDescription(optionalDescription ...interface{}) string {
	switch len(optionalDescription) {
	case 0:
		return ""
	case 1:
		if describe, ok := optionalDescription[0].(func() string); ok {
			return describe() + "\n"
		}
	}
	return fmt.Sprintf(optionalDescription[0].(string), optionalDescription[1:]...) + "\n"
}

<<<<<<< HEAD
func (assertion *AsyncAssertion) pollActual() (interface{}, error) {
=======
func (assertion *AsyncAssertion) processReturnValues(values []reflect.Value) (interface{}, error) {
	if len(values) == 0 {
		return nil, &asyncPolledActualError{
			message: fmt.Sprintf("The function passed to %s did not return any values", assertion.asyncType),
		}
	}

	actual := values[0].Interface()
	if _, ok := AsPollingSignalError(actual); ok {
		return actual, actual.(error)
	}

	var err error
	for i, extraValue := range values[1:] {
		extra := extraValue.Interface()
		if extra == nil {
			continue
		}
		if _, ok := AsPollingSignalError(extra); ok {
			return actual, extra.(error)
		}
		extraType := reflect.TypeOf(extra)
		zero := reflect.Zero(extraType).Interface()
		if reflect.DeepEqual(extra, zero) {
			continue
		}
		if i == len(values)-2 && extraType.Implements(errInterface) {
			err = extra.(error)
		}
		if err == nil {
			err = &asyncPolledActualError{
				message: fmt.Sprintf("The function passed to %s had an unexpected non-nil/non-zero return value at index %d:\n%s", assertion.asyncType, i+1, format.Object(extra, 1)),
			}
		}
	}

	return actual, err
}

func (assertion *AsyncAssertion) invalidFunctionError(t reflect.Type) error {
	return fmt.Errorf(`The function passed to %s had an invalid signature of %s.  Functions passed to %s must either:

	(a) have return values or
	(b) take a Gomega interface as their first argument and use that Gomega instance to make assertions.

You can learn more at https://onsi.github.io/gomega/#eventually
`, assertion.asyncType, t, assertion.asyncType)
}

func (assertion *AsyncAssertion) noConfiguredContextForFunctionError() error {
	return fmt.Errorf(`The function passed to %s requested a context.Context, but no context has been provided.  Please pass one in using %s().WithContext().

You can learn more at https://onsi.github.io/gomega/#eventually
`, assertion.asyncType, assertion.asyncType)
}

func (assertion *AsyncAssertion) argumentMismatchError(t reflect.Type, numProvided int) error {
	have := "have"
	if numProvided == 1 {
		have = "has"
	}
	return fmt.Errorf(`The function passed to %s has signature %s takes %d arguments but %d %s been provided.  Please use %s().WithArguments() to pass the corect set of arguments.

You can learn more at https://onsi.github.io/gomega/#eventually
`, assertion.asyncType, t, t.NumIn(), numProvided, have, assertion.asyncType)
}

func (assertion *AsyncAssertion) invalidMustPassRepeatedlyError(reason string) error {
	return fmt.Errorf(`Invalid use of MustPassRepeatedly with %s %s

You can learn more at https://onsi.github.io/gomega/#eventually
`, assertion.asyncType, reason)
}

func (assertion *AsyncAssertion) buildActualPoller() (func() (interface{}, error), error) {
>>>>>>> ef22b1c6a (Bump go-git)
	if !assertion.actualIsFunc {
		return assertion.actualValue, nil
	}

<<<<<<< HEAD
	values, err := assertion.actualFunc()
	if err != nil {
		return nil, err
=======
	var assertionFailure error
	inValues := []reflect.Value{}
	if takesGomega {
		inValues = append(inValues, reflect.ValueOf(NewGomega(assertion.g.DurationBundle).ConfigureWithFailHandler(func(message string, callerSkip ...int) {
			skip := 0
			if len(callerSkip) > 0 {
				skip = callerSkip[0]
			}
			_, file, line, _ := runtime.Caller(skip + 1)
			assertionFailure = &asyncPolledActualError{
				message: fmt.Sprintf("The function passed to %s failed at %s:%d with:\n%s", assertion.asyncType, file, line, message),
			}
			// we throw an asyncGomegaHaltExecutionError so that defer GinkgoRecover() can catch this error if the user makes an assertion in a goroutine
			panic(asyncGomegaHaltExecutionError{})
		})))
>>>>>>> ef22b1c6a (Bump go-git)
	}
	extras := []interface{}{nil}
	for _, value := range values[1:] {
		extras = append(extras, value.Interface())
	}
	success, message := vetActuals(extras, 0)
	if !success {
		return nil, errors.New(message)
	}

<<<<<<< HEAD
	return values[0].Interface(), nil
=======
	if !isVariadic && numIn != len(inValues) {
		return nil, assertion.argumentMismatchError(actualType, len(inValues))
	} else if isVariadic && len(inValues) < numIn-1 {
		return nil, assertion.argumentMismatchError(actualType, len(inValues))
	}

	if assertion.mustPassRepeatedly != 1 && assertion.asyncType != AsyncAssertionTypeEventually {
		return nil, assertion.invalidMustPassRepeatedlyError("it can only be used with Eventually")
	}
	if assertion.mustPassRepeatedly < 1 {
		return nil, assertion.invalidMustPassRepeatedlyError("parameter can't be < 1")
	}

	return func() (actual interface{}, err error) {
		var values []reflect.Value
		assertionFailure = nil
		defer func() {
			if numOut == 0 && takesGomega {
				actual = assertionFailure
			} else {
				actual, err = assertion.processReturnValues(values)
				_, isAsyncError := AsPollingSignalError(err)
				if assertionFailure != nil && !isAsyncError {
					err = assertionFailure
				}
			}
			if e := recover(); e != nil {
				if _, isAsyncError := AsPollingSignalError(e); isAsyncError {
					err = e.(error)
				} else if assertionFailure == nil {
					panic(e)
				}
			}
		}()
		values = actualValue.Call(inValues)
		return
	}, nil
>>>>>>> ef22b1c6a (Bump go-git)
}

func (assertion *AsyncAssertion) matcherMayChange(matcher types.GomegaMatcher, value interface{}) bool {
	if assertion.actualIsFunc {
		return true
	}
	return types.MatchMayChangeInTheFuture(matcher, value)
}

func (assertion *AsyncAssertion) match(matcher types.GomegaMatcher, desiredMatch bool, optionalDescription ...interface{}) bool {
	timer := time.Now()
	timeout := time.After(assertion.timeoutInterval)

<<<<<<< HEAD
	var matches bool
	var err error
	mayChange := true
	value, err := assertion.pollActual()
	if err == nil {
		mayChange = assertion.matcherMayChange(matcher, value)
		matches, err = matcher.Match(value)
	}

	assertion.g.THelper()

	fail := func(preamble string) {
		errMsg := ""
		message := ""
		if err != nil {
			errMsg = "Error: " + err.Error()
=======
	var matches, hasLastValidActual bool
	var actual, lastValidActual interface{}
	var actualErr, matcherErr error
	var oracleMatcherSaysStop bool

	assertion.g.THelper()

	pollActual, buildActualPollerErr := assertion.buildActualPoller()
	if buildActualPollerErr != nil {
		assertion.g.Fail(buildActualPollerErr.Error(), 2+assertion.offset)
		return false
	}

	actual, actualErr = pollActual()
	if actualErr == nil {
		lastValidActual = actual
		hasLastValidActual = true
		oracleMatcherSaysStop = assertion.matcherSaysStopTrying(matcher, actual)
		matches, matcherErr = assertion.pollMatcher(matcher, actual)
	}

	renderError := func(preamble string, err error) string {
		message := ""
		if pollingSignalErr, ok := AsPollingSignalError(err); ok {
			message = err.Error()
			for _, attachment := range pollingSignalErr.Attachments {
				message += fmt.Sprintf("\n%s:\n", attachment.Description)
				message += format.Object(attachment.Object, 1)
			}
		} else {
			message = preamble + "\n" + format.Object(err, 1)
		}
		return message
	}

	messageGenerator := func() string {
		// can be called out of band by Ginkgo if the user requests a progress report
		lock.Lock()
		defer lock.Unlock()
		message := ""

		if actualErr == nil {
			if matcherErr == nil {
				if desiredMatch != matches {
					if desiredMatch {
						message += matcher.FailureMessage(actual)
					} else {
						message += matcher.NegatedFailureMessage(actual)
					}
				} else {
					if assertion.asyncType == AsyncAssertionTypeConsistently {
						message += "There is no failure as the matcher passed to Consistently has not yet failed"
					} else {
						message += "There is no failure as the matcher passed to Eventually succeeded on its most recent iteration"
					}
				}
			} else {
				var fgErr formattedGomegaError
				if errors.As(actualErr, &fgErr) {
					message += fgErr.FormattedGomegaError() + "\n"
				} else {
					message += renderError(fmt.Sprintf("The matcher passed to %s returned the following error:", assertion.asyncType), matcherErr)
				}
			}
>>>>>>> ef22b1c6a (Bump go-git)
		} else {
			var fgErr formattedGomegaError
			if errors.As(actualErr, &fgErr) {
				message += fgErr.FormattedGomegaError() + "\n"
			} else {
				message += renderError(fmt.Sprintf("The function passed to %s returned the following error:", assertion.asyncType), actualErr)
			}
			if hasLastValidActual {
				message += fmt.Sprintf("\nAt one point, however, the function did return successfully.\nYet, %s failed because", assertion.asyncType)
				_, e := matcher.Match(lastValidActual)
				if e != nil {
					message += renderError(" the matcher returned the following error:", e)
				} else {
					message += " the matcher was not satisfied:\n"
					if desiredMatch {
						message += matcher.FailureMessage(lastValidActual)
					} else {
						message += matcher.NegatedFailureMessage(lastValidActual)
					}
				}
			}
		}
<<<<<<< HEAD
=======

		description := assertion.buildDescription(optionalDescription...)
		return fmt.Sprintf("%s%s", description, message)
	}

	fail := func(preamble string) {
>>>>>>> ef22b1c6a (Bump go-git)
		assertion.g.THelper()
		description := assertion.buildDescription(optionalDescription...)
		assertion.g.Fail(fmt.Sprintf("%s after %.3fs.\n%s%s%s", preamble, time.Since(timer).Seconds(), description, message, errMsg), 3+assertion.offset)
	}

<<<<<<< HEAD
	if assertion.asyncType == AsyncAssertionTypeEventually {
		for {
			if err == nil && matches == desiredMatch {
				return true
=======
	var contextDone <-chan struct{}
	if assertion.ctx != nil {
		contextDone = assertion.ctx.Done()
		if v, ok := assertion.ctx.Value("GINKGO_SPEC_CONTEXT").(contextWithAttachProgressReporter); ok {
			detach := v.AttachProgressReporter(messageGenerator)
			defer detach()
		}
	}

	// Used to count the number of times in a row a step passed
	passedRepeatedlyCount := 0
	for {
		var nextPoll <-chan time.Time = nil
		var isTryAgainAfterError = false

		for _, err := range []error{actualErr, matcherErr} {
			if pollingSignalErr, ok := AsPollingSignalError(err); ok {
				if pollingSignalErr.IsStopTrying() {
					fail("Told to stop trying")
					return false
				}
				if pollingSignalErr.IsTryAgainAfter() {
					nextPoll = time.After(pollingSignalErr.TryAgainDuration())
					isTryAgainAfterError = true
				}
			}
		}

		if actualErr == nil && matcherErr == nil && matches == desiredMatch {
			if assertion.asyncType == AsyncAssertionTypeEventually {
				passedRepeatedlyCount += 1
				if passedRepeatedlyCount == assertion.mustPassRepeatedly {
					return true
				}
>>>>>>> ef22b1c6a (Bump go-git)
			}

			if !mayChange {
				fail("No future change is possible.  Bailing out early")
				return false
			}

			select {
			case <-time.After(assertion.pollingInterval):
				value, err = assertion.pollActual()
				if err == nil {
					mayChange = assertion.matcherMayChange(matcher, value)
					matches, err = matcher.Match(value)
				}
			case <-timeout:
				fail("Timed out")
				return false
			}
		}
	} else if assertion.asyncType == AsyncAssertionTypeConsistently {
		for {
			if !(err == nil && matches == desiredMatch) {
				fail("Failed")
				return false
			}
<<<<<<< HEAD
=======
			// Reset the consecutive pass count
			passedRepeatedlyCount = 0
		}
>>>>>>> ef22b1c6a (Bump go-git)

			if !mayChange {
				return true
			}

<<<<<<< HEAD
			select {
			case <-time.After(assertion.pollingInterval):
				value, err = assertion.pollActual()
				if err == nil {
					mayChange = assertion.matcherMayChange(matcher, value)
					matches, err = matcher.Match(value)
=======
		if nextPoll == nil {
			nextPoll = assertion.afterPolling()
		}

		select {
		case <-nextPoll:
			a, e := pollActual()
			lock.Lock()
			actual, actualErr = a, e
			lock.Unlock()
			if actualErr == nil {
				lock.Lock()
				lastValidActual = actual
				hasLastValidActual = true
				lock.Unlock()
				oracleMatcherSaysStop = assertion.matcherSaysStopTrying(matcher, actual)
				m, e := assertion.pollMatcher(matcher, actual)
				lock.Lock()
				matches, matcherErr = m, e
				lock.Unlock()
			}
		case <-contextDone:
			fail("Context was cancelled")
			return false
		case <-timeout:
			if assertion.asyncType == AsyncAssertionTypeEventually {
				fail("Timed out")
				return false
			} else {
				if isTryAgainAfterError {
					fail("Timed out while waiting on TryAgainAfter")
					return false
>>>>>>> ef22b1c6a (Bump go-git)
				}
			case <-timeout:
				return true
			}
		}
	}

	return false
}
