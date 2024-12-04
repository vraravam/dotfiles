module.exports = {
  'root': true,
  'rules': {
    'indent': [
            2,
            2,
      {
        'SwitchCase': 1
      }
        ],
    'quotes': [
            2,
            'single'
        ],
    'linebreak-style': [
            2,
            'unix'
        ],
    'semi': [
            2,
            'always'
        ],
    // Best practices
    'block-scoped-var': 1,
    'complexity': [1, 4],
    'consistent-return': 1,
    'curly': 1,
    'default-case': 1,
    'dot-location': [1, 'property'],
    'dot-notation': 1,
    'eqeqeq': 2,
    'guard-for-in': 1,
    'no-alert': 2,
    'no-caller': 2,
    'no-case-declarations': 2,
    'no-console': 0,
    'no-div-regex': 1,
    'no-else-return': 0,
    'no-empty': 0,
    'no-empty-pattern': 2,
    'no-eq-null': 2,
    'no-eval': 2,
    'no-extend-native': 1,
    'no-extra-bind': 1,
    'no-fallthrough': 1,
    'no-floating-decimal': 1,
    'no-implicit-coercion': 1,
    'no-implied-eval': 1,
    'no-invalid-this': 2,
    'no-iterator': 2,
    'no-labels': 1,
    'no-lone-blocks': 1,
    'no-loop-func': 2,
    'no-magic-numbers': [2, {
      'ignore': [-1, 0, 1, 2, 100, 200, 422, 3600000, 1453449120000, 1453445460000]
    }],
    'no-multi-spaces': 1,
    'no-multi-str': 1,
    'no-native-reassign': 1,
    'no-new-func': 2,
    'no-new-wrappers': 2,
    'no-new': 1,
    'no-octal-escape': 1,
    'no-octal': 1,
    'no-param-reassign': 1,
    'no-process-env': 2,
    'no-proto': 2,
    'no-redeclare': 1,
    'no-return-assign': 2,
    'no-script-url': 2,
    'no-self-compare': 1,
    'no-sequences': 1,
    'no-throw-literal': 2,
    'no-unused-expressions': [1, { allowTernary: true } ],
    'no-useless-call': 2,
    'no-useless-concat': 1,
    'no-void': 2,
    'no-warning-comments': 0,
    'no-with': 2,
    'radix': 1,
    'vars-on-top': 0,
    'wrap-iife': 2,
    'yoda': 0,
    // Strict mode
    'strict': 1,
    // Variables
    'init-declarations': 0,
    'no-catch-shadow': 2,
    'no-delete-var': 2,
    'no-label-var': 2,
    'no-shadow-restricted-names': 2,
    'no-shadow': 2,
    'no-undef-init': 1,
    'no-undef': 2,
    'no-undefined': 0,
    'no-unused-vars': 2,
    'no-use-before-define': 2
  },
  'env': {
    'browser': true
  },
  'extends': 'defaults',
  'globals': {
    '_': false,
    '$': false,
    'after': false,
    'afterEach': false,
    'angular': false,
    'App': false,
    'Backbone': false,
    'before': false,
    'beforeEach': false,
    'bootbox': false,
    'cordova': false,
    'describe': false,
    'expect': false,
    'I18n': false,
    'inject': false,
    'it': false,
    'jasmine': false,
    'JST': false,
    'module': false,
    'moment': false,
    'process': false,
    'require': false,
    'Routes': false,
    'spyOn': false
  },
  'plugins': [
    'eslint-plugin-backbone',
    'eslint-plugin-html'
  ]
};
