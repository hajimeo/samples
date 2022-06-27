/*
 * Copyright (c) 2008, 2015, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the Classpath exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */


import org.openjdk.btrace.core.annotations.BTrace;
import org.openjdk.btrace.core.annotations.OnMethod;
import org.openjdk.btrace.core.annotations.OnTimer;
import org.openjdk.btrace.core.annotations.Self;

import java.awt.*;

import static org.openjdk.btrace.core.BTraceUtils.println;

/**
 * A BTrace program that can be run against a GUI
 * program. This program prints (monotonic) count of
 * number of java.awt.Components created once every
 * 2 seconds (2000 milliseconds).
 */

@BTrace
public class NewComponent {
    // component count
    private static volatile long count;

    @OnMethod(
            clazz = "java.awt.Component",
            method = "<init>"
    )
    public static void onnew(@Self Component c) {
        // increment counter on constructor entry
        count++;
    }

    @OnTimer(2000)
    public static void print() {
        // print the counter
        println("component count = " + count);
    }
}
