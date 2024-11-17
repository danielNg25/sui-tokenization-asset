#[test_only]

module tokenization::test_utils {
    public fun assert_approx_abs(value: u64, expected: u64, tolerance: u64) {
        if (value >= expected) {
            assert!(value - expected <= tolerance);
        } else {
            assert!(expected - value <= tolerance);
        }
    }

    public fun assert_approx_rel(value: u64, expected: u64, tolerance: u64) {
        if (value >= expected) {
            assert!(value - expected <= expected * tolerance / 10000);
        } else {
            assert!(expected - value <= expected * tolerance / 10000);
        }
    }

    public fun assert_approx_abs_u128(value: u128, expected: u128, tolerance: u128) {
        if (value >= expected) {
            assert!(value - expected <= tolerance);
        } else {
            assert!(expected - value <= tolerance);
        }
    }

    public fun assert_approx_rel_u128(value: u128, expected: u128, tolerance: u128) {
        if (value >= expected) {
            assert!(value - expected <= expected * tolerance / 10000);
        } else {
            assert!(expected - value <= expected * tolerance / 10000);
        }
    }
}