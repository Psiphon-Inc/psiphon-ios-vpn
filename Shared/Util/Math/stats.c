/*
 * Copyright (c) 2020, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "stats.h"
#include <math.h>

// Proposal: in the future return NAN if vals is
// NULL or zero length.
double double_mean(double *vals, int length) {
    double runningTotal = 0.0;

    for (int i = 0; i < length; i++) {
        runningTotal += vals[i];
    }

    return runningTotal / length;
}

// Proposal: in the future return NAN if vals is
// NULL or zero length.
double double_stdev(double *vals, int length) {
    double mean = double_mean(vals, length);
    double sumOfSquaredDifferences = 0.0;

    for (int i = 0; i < length; i++) {
        double difference = vals[i] - mean;
        sumOfSquaredDifferences += difference * difference;
    }

    return sqrt(sumOfSquaredDifferences / (length - 1));
}

