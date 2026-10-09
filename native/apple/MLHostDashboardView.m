// SPDX-License-Identifier: MIT
#import "MLHostDashboardView.h"

@implementation MLHostDashboardView {
    UILabel *_title, *_message, *_metrics;
    UIButton *_retry, *_wake, *_pair, *_bandwidth;
}
- (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = UIColor.whiteColor; label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
        self.layer.cornerRadius = 20;
        _title = [self labelWithSize:38 weight:UIFontWeightSemibold];
        _message = [self labelWithSize:25 weight:UIFontWeightRegular];
        _metrics = [self labelWithSize:22 weight:UIFontWeightRegular];
        _metrics.textColor = [UIColor colorWithWhite:0.85 alpha:1];
        _metrics.accessibilityIdentifier = @"HostNetworkMetrics";
        _retry = [self button:@"Retry" action:@selector(retry)];
        _wake = [self button:@"Wake PC" action:@selector(wake)];
        _pair = [self button:@"Pair PC" action:@selector(pair)];
        _bandwidth = [self button:@"Test bandwidth" action:@selector(bandwidth)];
        UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_retry, _wake, _pair, _bandwidth]];
        buttons.axis = UILayoutConstraintAxisHorizontal; buttons.spacing = 40; buttons.alignment = UIStackViewAlignmentCenter;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _message, _metrics, buttons]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 18; stack.alignment = UIStackViewAlignmentCenter;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:36],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-36],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:24],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-24],
            [_metrics.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [_message.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
        ]];
    }
    return self;
}
- (void)showSnapshot:(MLHostNetworkSnapshot *)snapshot canWake:(BOOL)canWake {
    BOOL ready = snapshot.state == MLHostDashboardReady;
    _title.hidden = ready;
    switch (snapshot.state) {
        case MLHostDashboardReady: _title.text = @""; break;
        case MLHostDashboardChecking: _title.text = @"Checking PC…"; break;
        case MLHostDashboardServiceUnavailable: _title.text = @"Streaming service unavailable"; break;
        case MLHostDashboardUnreachable: _title.text = @"PC unreachable"; break;
        case MLHostDashboardPairRequired: _title.text = @"Pair this PC"; break;
    }
    _message.text = snapshot.message; _message.hidden = snapshot.message.length == 0;
    _metrics.text = snapshot.metrics;
    _retry.hidden = ready;
    _wake.hidden = ready || !canWake || snapshot.state == MLHostDashboardPairRequired;
    _pair.hidden = snapshot.state != MLHostDashboardPairRequired;
    _bandwidth.hidden = !ready;
    _bandwidth.enabled = snapshot.canTestBandwidth;
    self.accessibilityIdentifier = ready ? @"HostNetworkFooter" : @"HostStatusPanel";
}
- (void)retry { if (self.retryAction) self.retryAction(); }
- (void)wake { if (self.wakeAction) self.wakeAction(); }
- (void)pair { if (self.pairAction) self.pairAction(); }
- (void)bandwidth { if (self.bandwidthAction) self.bandwidthAction(); }
@end
