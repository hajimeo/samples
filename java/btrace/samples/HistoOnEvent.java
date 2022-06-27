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
import org.openjdk.btrace.core.annotations.OnEvent;
import org.openjdk.btrace.core.annotations.OnMethod;
import org.openjdk.btrace.core.annotations.Self;

import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.openjdk.btrace.core.BTraceUtils.*;

/**
 * This sample collects histogram of javax.swing.JComponets
 * created by traced app. But, the histogram is printed only
 * on event (from client).
 */
@BTrace
public class HistoOnEvent {
    private static Map<String, AtomicInteger> histo = newHashMap();

    @OnMethod(
            clazz = "javax.swing.JComponent",
            method = "<init>"
    )
    public static void onnewObject(@Self Object obj) {
        String cn = name(classOf(obj));
        AtomicInteger ai = get(histo, cn);
        if (ai == null) {
            ai = newAtomicInteger(1);
            put(histo, cn, ai);
        } else {
            incrementAndGet(ai);
        }
    }

    @OnEvent
    public static void print() {
        if (size(histo) != 0) {
            printNumberMap("Component Histogram", histo);
        }
    }
}
