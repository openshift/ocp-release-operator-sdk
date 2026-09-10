// Copyright 2024 The Operator-SDK Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");

// Commitlint configuration with downstream compatibility.
// Accepts:
//   <subsystem>: <subject>               (upstream convention)
//   UPSTREAM: <carry|drop>: <subject>    (downstream convention)
//   type(scope): subject                 (Conventional Commits, optional)
module.exports = {
  rules: {
    'header-max-length': [2, 'always', 70],
    'body-max-line-length': [1, 'always', 80],
    'downstream-header-pattern': [2, 'always'],
  },
  plugins: [
    {
      rules: {
        'downstream-header-pattern': ({header}) => {
          if (!header) {
            return [false, 'commit message must not be empty'];
          }

          const patterns = [
            /^UPSTREAM:\s+<(carry|drop)>:\s+\S/,
            /^[a-zA-Z][a-zA-Z0-9/_.()\-]*:\s+\S/,
          ];

          const valid = patterns.some(p => p.test(header));
          return [
            valid,
            'header must match "<subsystem>: <subject>" or "UPSTREAM: <carry|drop>: <subject>"',
          ];
        },
      },
    },
  ],
};
