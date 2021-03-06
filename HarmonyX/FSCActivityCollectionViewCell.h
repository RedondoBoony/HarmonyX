//
//  FSCActivityCollectionViewCell.h
//  HarmonyX
//
//  Created by Philippe Boudreau on 2014-11-09.
//  Copyright (c) 2014 Fasterre. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "FSCActivity.h"

static NSString * const FSCActtivityCellIdentifier = @"ActivityCell";

@interface FSCActivityCollectionViewCell : UICollectionViewCell

@property (nonatomic, strong) FSCActivity * activity;

- (void) setActivity: (FSCActivity *) activity
       withMaskColor: (UIColor *) maskColor
     backgroundColor: (UIColor *) backgroundColor;

@end
